import Foundation
import Testing
@testable import CleanerCore

@Suite("CleanupService and database")
struct CleanupServiceTests {

    private func setup() async throws -> (Fixture, OperationLog, CleanupService, AppDatabase, [Finding]) {
        let fx = try Fixture()
        try fx.file("home/Library/Caches/com.example.a/x", bytes: 8192)
        try fx.file("home/Library/Logs/old.log", bytes: 4096)
        try fx.file("home/.Trash/thing.txt", bytes: 2048)
        let log = OperationLog()
        let ctx = fx.context(log: log)
        let db = try AppDatabase.inMemory()
        let modules = ModuleRegistry.standard(context: ctx)
        var findings: [Finding] = []
        for module in modules { findings += await module.scan() }
        return (fx, log, CleanupService(modules: modules, database: db), db, findings)
    }

    @Test func dryRunLogsWhatWouldBeRemovedAndChangesNothing() async throws {
        let (fx, log, service, db, findings) = try await setup()
        let before = fx.treeSnapshot()

        let result = await service.clean(findings, mode: .dryRun)

        #expect(fx.treeSnapshot() == before)
        #expect(log.calls.isEmpty)
        #expect(result.removed.count == 3)
        let entries = try db.recentActions()
        #expect(entries.count == 3)
        #expect(entries.allSatisfy { $0.outcome == .simulated && $0.mode == .dryRun })
        #expect(Set(entries.map(\.category)) == [.systemCache, .applicationLogs, .trash])
    }

    @Test func realCleanLogsMovedAndSkippedItems() async throws {
        let (fx, _, service, db, findings) = try await setup()

        // Trash items are refused in Move to Trash mode and logged as skipped.
        let result = await service.clean(findings, mode: .moveToTrash)

        #expect(result.removed.count == 2)
        #expect(result.failed.count == 1)
        #expect(fx.exists("home/.Trash/thing.txt"))
        let entries = try db.recentActions()
        #expect(entries.filter { $0.outcome == .movedToTrash }.count == 2)
        #expect(entries.filter { $0.outcome == .movedToTrash }.allSatisfy { $0.trashedPath?.contains("FakeTrash") == true })
        let skipped = try #require(entries.first { $0.outcome == .skipped })
        #expect(skipped.category == .trash)
        #expect(skipped.detail?.contains("Delete permanently") == true)
    }

    @Test func exclusionsRoundTrip() throws {
        let fx = try Fixture()
        try fx.dir("keep")
        let db = try AppDatabase.inMemory()
        // Store the canonical path even when given the /var alias.
        let aliased = URL(fileURLWithPath: fx.path("keep").replacingOccurrences(of: "/private/var/", with: "/var/"))
        try db.addExclusion(aliased)
        try db.addExclusion(aliased)
        #expect(try db.exclusions().map(\.path) == [fx.root.path + "/keep"])
        try db.removeExclusion(path: fx.root.path + "/keep")
        #expect(try db.exclusions().isEmpty)
    }

    @Test func scanHistoryReturnsLatest() throws {
        let db = try AppDatabase.inMemory()
        let t = Date()
        try db.saveScan(ScanRecord(startedAt: t, finishedAt: t.addingTimeInterval(5), junkBytes: 10, junkItemCount: 1, threatCount: 0, performanceIssueCount: 0))
        let second = try db.saveScan(ScanRecord(startedAt: t.addingTimeInterval(60), finishedAt: t.addingTimeInterval(70), junkBytes: 20, junkItemCount: 2, threatCount: 1, performanceIssueCount: 3))
        #expect(second.id != nil)
        #expect(try db.lastScan()?.junkBytes == 20)
    }
}
