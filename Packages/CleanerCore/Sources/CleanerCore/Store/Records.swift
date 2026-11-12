import Foundation
import GRDB

/// One line of the in-app activity log: something moved, deleted, simulated
/// (dry run) or skipped.
public struct ActionLogEntry: Codable, Sendable, Hashable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public enum Outcome: String, Codable, Sendable {
        case movedToTrash
        case deleted
        case simulated
        case skipped
    }

    public var id: Int64?
    public var date: Date
    public var mode: RemovalMode
    public var category: CleanupCategory
    public var target: String
    public var bytes: Int64
    public var outcome: Outcome
    public var detail: String?
    public var trashedPath: String?

    public static let databaseTableName = "actionLog"

    public init(
        id: Int64? = nil, date: Date, mode: RemovalMode, category: CleanupCategory, target: String,
        bytes: Int64, outcome: Outcome, detail: String? = nil, trashedPath: String? = nil
    ) {
        self.id = id
        self.date = date
        self.mode = mode
        self.category = category
        self.target = target
        self.bytes = bytes
        self.outcome = outcome
        self.detail = detail
        self.trashedPath = trashedPath
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// A path the user never wants offered for cleaning.
public struct Exclusion: Codable, Sendable, Hashable, Identifiable, FetchableRecord, PersistableRecord {
    public var path: String
    public var addedAt: Date
    public var id: String { path }

    public static let databaseTableName = "exclusion"

    public init(path: String, addedAt: Date = Date()) {
        self.path = path
        self.addedAt = addedAt
    }

    public var url: URL { URL(fileURLWithPath: path) }
}

/// Summary of one Smart Care scan.
public struct ScanRecord: Codable, Sendable, Hashable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var startedAt: Date
    public var finishedAt: Date
    public var junkBytes: Int64
    public var junkItemCount: Int
    public var threatCount: Int
    public var performanceIssueCount: Int

    public static let databaseTableName = "scanHistory"

    public init(
        id: Int64? = nil, startedAt: Date, finishedAt: Date, junkBytes: Int64,
        junkItemCount: Int, threatCount: Int, performanceIssueCount: Int
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.junkBytes = junkBytes
        self.junkItemCount = junkItemCount
        self.threatCount = threatCount
        self.performanceIssueCount = performanceIssueCount
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
