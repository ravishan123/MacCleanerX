import Darwin
import Foundation

/// An app bundle found in an Applications folder.
public struct InstalledApp: Sendable, Hashable, Identifiable {
    public let url: URL
    public let name: String
    public let bundleID: String?
    public let version: String?
    public let teamID: String?
    public let signature: SignatureStatus
    public let isAppStore: Bool
    public let isOwnedByUser: Bool
    public var sizeBytes: Int64?
    /// Why the app can't be uninstalled by Mac Cleaner, if it can't.
    public let blockReason: String?

    public var id: String { url.path }
    public var canUninstall: Bool { blockReason == nil }
}

public enum AppInventory {
    public static func liveFolders(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [URL(fileURLWithPath: "/Applications", isDirectory: true),
         home.appending(path: "Applications", directoryHint: .isDirectory)]
    }

    /// Top-level apps plus apps one folder down (e.g. /Applications/Utilities).
    /// Read-only. Sizes are filled in separately by `withSizes`.
    public static func apps(in folders: [URL], appGuard: AppBundleGuard) -> [InstalledApp] {
        let running = runningExecutablePaths()
        var urls: [URL] = []
        for folder in folders {
            let entries = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for entry in entries {
                if entry.pathExtension == "app" {
                    urls.append(entry)
                } else if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    urls += ((try? FileManager.default.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
                        .filter { $0.pathExtension == "app" }
                }
            }
        }
        return urls.map { describe($0, appGuard: appGuard, running: running) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func describe(_ url: URL, appGuard: AppBundleGuard, running: [String]) -> InstalledApp {
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary ?? [:]
        let signature = SignatureChecker.status(of: url)
        let team: String? = switch signature {
        case .appStore(let t), .developerID(let t), .otherCertificate(let t): t
        default: nil
        }
        var st = stat()
        let owned = lstat(url.path(percentEncoded: false), &st) == 0 && st.st_uid == getuid()
        let reason: String?
        do {
            _ = try appGuard.validate(url, running: running)
            reason = nil
        } catch {
            reason = error.description
        }
        return InstalledApp(
            url: url,
            name: (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent,
            bundleID: bundle?.bundleIdentifier,
            version: info["CFBundleShortVersionString"] as? String,
            teamID: team,
            signature: signature,
            isAppStore: AppBundleGuard.isAppStoreApp(url, signature: signature),
            isOwnedByUser: owned,
            sizeBytes: nil,
            blockReason: reason
        )
    }

    /// Executable paths of every process we can see.
    public static func runningExecutablePaths() -> [String] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let found = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard found > 0 else { return [] }
        var paths: [String] = []
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for pid in pids.prefix(Int(found)) where pid > 0 {
            if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
                paths.append(String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
            }
        }
        return paths
    }
}
