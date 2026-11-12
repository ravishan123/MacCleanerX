import Foundation
import GRDB

/// SQLite storage for the action log, exclusions and scan history.
public final class AppDatabase: Sendable {
    private let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// `~/Library/Application Support/Mac Cleaner/MacCleaner.sqlite`
    public static func openDefault() throws -> AppDatabase {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let folder = support.appending(path: "Mac Cleaner", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pool = try DatabasePool(path: folder.appending(path: "MacCleaner.sqlite").path(percentEncoded: false))
        return try AppDatabase(pool)
    }

    /// In-memory database for tests and previews.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: ActionLogEntry.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("date", .datetime).notNull().indexed()
                t.column("mode", .text).notNull()
                t.column("category", .text).notNull()
                t.column("target", .text).notNull()
                t.column("bytes", .integer).notNull()
                t.column("outcome", .text).notNull()
                t.column("detail", .text)
                t.column("trashedPath", .text)
            }
            try db.create(table: Exclusion.databaseTableName) { t in
                t.primaryKey("path", .text)
                t.column("addedAt", .datetime).notNull()
            }
            try db.create(table: ScanRecord.databaseTableName) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("startedAt", .datetime).notNull()
                t.column("finishedAt", .datetime).notNull().indexed()
                t.column("junkBytes", .integer).notNull()
                t.column("junkItemCount", .integer).notNull()
                t.column("threatCount", .integer).notNull()
                t.column("performanceIssueCount", .integer).notNull()
            }
        }
        return migrator
    }

    // MARK: Action log

    public func appendActions(_ entries: [ActionLogEntry]) throws {
        try writer.write { db in
            for var entry in entries { try entry.insert(db) }
        }
    }

    public func recentActions(limit: Int = 500) throws -> [ActionLogEntry] {
        try writer.read { db in
            try ActionLogEntry.order(Column("date").desc, Column("id").desc).limit(limit).fetchAll(db)
        }
    }

    public func clearActionLog() throws {
        _ = try writer.write { db in try ActionLogEntry.deleteAll(db) }
    }

    // MARK: Exclusions

    public func exclusions() throws -> [Exclusion] {
        try writer.read { db in try Exclusion.order(Column("path")).fetchAll(db) }
    }

    public func addExclusion(_ url: URL) throws {
        let path = SafetyGuard.realpath(url.path(percentEncoded: false)) ?? url.standardizedFileURL.path
        try writer.write { db in try Exclusion(path: path).save(db) }
    }

    public func removeExclusion(path: String) throws {
        _ = try writer.write { db in try Exclusion.deleteOne(db, key: path) }
    }

    // MARK: Scan history

    @discardableResult
    public func saveScan(_ record: ScanRecord) throws -> ScanRecord {
        try writer.write { db in
            var copy = record
            try copy.insert(db)
            return copy
        }
    }

    public func lastScan() throws -> ScanRecord? {
        try writer.read { db in try ScanRecord.order(Column("finishedAt").desc).fetchOne(db) }
    }
}
