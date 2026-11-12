import Foundation

/// How selected findings are removed.
public enum RemovalMode: String, Sendable, Codable, Hashable {
    /// Default. Items go to the user's Trash and can be put back.
    case moveToTrash
    /// Opt-in, requires an extra confirmation in the UI.
    case deletePermanently
    /// Validate and log what would be removed without touching anything.
    case dryRun
}

public struct CleanResult: Sendable, Hashable {
    public struct Removed: Sendable, Hashable {
        public let findingID: UUID
        public let target: FindingTarget
        public let bytes: Int64
        /// Where the item ended up when moved to the Trash.
        public let trashedURL: URL?
    }

    public struct Failed: Sendable, Hashable {
        public let findingID: UUID
        public let target: FindingTarget
        public let reason: String
    }

    public let mode: RemovalMode
    public var removed: [Removed]
    public var failed: [Failed]

    public init(mode: RemovalMode, removed: [Removed] = [], failed: [Failed] = []) {
        self.mode = mode
        self.removed = removed
        self.failed = failed
    }

    /// For `.dryRun` this is the space that *would* be freed.
    public var bytesFreed: Int64 { removed.reduce(0) { $0 + $1.bytes } }

    public static func merged(_ results: [CleanResult], mode: RemovalMode) -> CleanResult {
        CleanResult(
            mode: mode,
            removed: results.flatMap(\.removed),
            failed: results.flatMap(\.failed)
        )
    }
}
