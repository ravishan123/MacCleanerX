import Foundation

/// A launchd job definition (LaunchAgent or LaunchDaemon plist).
public struct LaunchItem: Sendable, Hashable {
    public enum Scope: String, Sendable, Hashable {
        case userAgent, systemAgent, systemDaemon

        public var displayName: String {
            switch self {
            case .userAgent: "Your startup items"
            case .systemAgent: "Startup items for all users"
            case .systemDaemon: "Background services"
            }
        }
    }

    public let plist: URL
    public let scope: Scope
    public let label: String?
    /// `Program`, or the first element of `ProgramArguments`.
    public let program: String?
    public let arguments: [String]
    public let runAtLoad: Bool
    public let keepAlive: Bool
    /// True for jobs registered by an app via SMAppService (`BundleProgram`),
    /// whose program path is relative to the app bundle.
    public let isBundleProgram: Bool
    public let isReadable: Bool

    public var startsAutomatically: Bool { runAtLoad || keepAlive }
    public var isHidden: Bool {
        plist.lastPathComponent.hasPrefix(".") || (label?.hasPrefix(".") ?? false)
    }
    public var isApple: Bool { label?.hasPrefix("com.apple.") ?? false }
    public var displayName: String { label ?? plist.deletingPathExtension().lastPathComponent }
}

public enum LaunchItemInventory {
    public static func standardFolders(home: URL) -> [(URL, LaunchItem.Scope)] {
        [
            (home.appending(path: "Library/LaunchAgents", directoryHint: .isDirectory), .userAgent),
            (URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true), .systemAgent),
            (URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true), .systemDaemon),
        ]
    }

    /// Read-only: parses every `.plist` in the given folders (hidden ones too).
    public static func items(in folders: [(URL, LaunchItem.Scope)]) -> [LaunchItem] {
        folders.flatMap { folder, scope -> [LaunchItem] in
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: []
            )) ?? []
            return entries
                .filter { $0.pathExtension == "plist" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .map { parse($0, scope: scope) }
        }
    }

    static func parse(_ url: URL, scope: LaunchItem.Scope) -> LaunchItem {
        guard let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return LaunchItem(plist: url, scope: scope, label: nil, program: nil, arguments: [],
                              runAtLoad: false, keepAlive: false, isBundleProgram: false, isReadable: false)
        }
        let arguments = dict["ProgramArguments"] as? [String] ?? []
        let keepAlive: Bool = switch dict["KeepAlive"] {
        case let flag as Bool: flag
        case is [String: Any]: true // conditional keep-alive still restarts the job
        default: false
        }
        return LaunchItem(
            plist: url,
            scope: scope,
            label: dict["Label"] as? String,
            program: (dict["Program"] as? String) ?? arguments.first,
            arguments: arguments,
            runAtLoad: dict["RunAtLoad"] as? Bool ?? false,
            keepAlive: keepAlive,
            isBundleProgram: dict["BundleProgram"] != nil,
            isReadable: true
        )
    }

    /// launchd resolves bare program names against a fixed search path.
    static func resolveProgram(_ program: String) -> String {
        guard !program.hasPrefix("/") else { return program }
        for dir in ["/usr/bin", "/bin", "/usr/sbin", "/sbin"] {
            let candidate = dir + "/" + program
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
        }
        return program
    }
}
