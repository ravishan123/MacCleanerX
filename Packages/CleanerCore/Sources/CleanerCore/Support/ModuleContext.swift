import Foundation

/// The roots, clock and side-effecting services a module works against.
///
/// Production code uses `.live()`. Tests build their own context that points
/// every root at a throwaway fixture folder and injects fake file operations,
/// so no test can ever reach the real ~/Library, ~/Downloads or Trash.
/// `operations` deliberately has no default value for that reason, and
/// `commandRunner` defaults to one that refuses everything.
public struct ModuleContext: Sendable {
    public var home: URL
    public var temporaryDirectory: URL
    public var operations: FileOperations
    public var commandRunner: CommandRunner
    public var openFiles: @Sendable () -> OpenFileSnapshot
    public var now: @Sendable () -> Date
    /// Items modified more recently than this are skipped (default 10 minutes).
    public var recentModificationWindow: TimeInterval
    /// User exclusions: these paths and everything inside them are never
    /// offered or removed.
    public var exclusions: [URL] {
        didSet { exclusionPaths = Self.resolve(exclusions) }
    }
    private var exclusionPaths: [String]

    public init(
        home: URL,
        temporaryDirectory: URL,
        operations: FileOperations,
        commandRunner: CommandRunner = .unavailable,
        openFiles: @escaping @Sendable () -> OpenFileSnapshot = { OpenFileSnapshot.capture() },
        now: @escaping @Sendable () -> Date = { Date() },
        recentModificationWindow: TimeInterval = 10 * 60,
        exclusions: [URL] = []
    ) {
        self.home = home
        self.temporaryDirectory = temporaryDirectory
        self.operations = operations
        self.commandRunner = commandRunner
        self.openFiles = openFiles
        self.now = now
        self.recentModificationWindow = recentModificationWindow
        self.exclusions = exclusions
        self.exclusionPaths = Self.resolve(exclusions)
    }

    public static func live(exclusions: [URL] = []) -> ModuleContext {
        ModuleContext(
            home: FileManager.default.homeDirectoryForCurrentUser,
            temporaryDirectory: FileManager.default.temporaryDirectory,
            operations: .live,
            commandRunner: .live,
            exclusions: exclusions
        )
    }

    public func isExcluded(_ url: URL) -> Bool {
        guard !exclusionPaths.isEmpty else { return false }
        let path = SafetyGuard.realpath(url.path(percentEncoded: false)) ?? url.standardizedFileURL.path
        return exclusionPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    private static func resolve(_ urls: [URL]) -> [String] {
        urls.map { SafetyGuard.realpath($0.path(percentEncoded: false)) ?? $0.standardizedFileURL.path }
            .map { $0.count > 1 && $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
    }

    public var library: URL { home.appending(path: "Library", directoryHint: .isDirectory) }
    public var caches: URL { library.appending(path: "Caches", directoryHint: .isDirectory) }
    public var logs: URL { library.appending(path: "Logs", directoryHint: .isDirectory) }
    public var downloads: URL { home.appending(path: "Downloads", directoryHint: .isDirectory) }
    public var trash: URL { home.appending(path: ".Trash", directoryHint: .isDirectory) }
    public var developer: URL { library.appending(path: "Developer", directoryHint: .isDirectory) }
}
