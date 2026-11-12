import Foundation
import Testing
@testable import CleanerCore

/// Layout: <fixture>/allowed is the only allowlist root, <fixture>/outside
/// must never be touched. All operations go to the fixture's FakeTrash.
@Suite("Remover")
struct RemoverTests {

    private struct Setup {
        let fx: Fixture
        let log: OperationLog
        let context: ModuleContext
        let safetyGuard: SafetyGuard
        var remover: Remover { Remover(safetyGuard: safetyGuard, context: context) }

        func findings(_ relatives: [String]) -> [Finding] {
            let builder = FindingBuilder(
                category: .systemCache, risk: .safe, safetyGuard: safetyGuard,
                context: context, openFiles: .empty
            )
            return relatives.compactMap { builder.make(fx.url($0), group: "Test") }
        }
    }

    private func setup(clockOffset: TimeInterval = 3600) throws -> Setup {
        let fx = try Fixture()
        try fx.file("allowed/a.txt", bytes: 4096)
        try fx.file("allowed/b.txt", bytes: 4096)
        try fx.file("allowed/folder/c.txt", bytes: 4096)
        try fx.file("outside/secret.txt")
        let log = OperationLog()
        return Setup(
            fx: fx,
            log: log,
            context: fx.context(log: log, clockOffset: clockOffset),
            safetyGuard: SafetyGuard(allowedRoots: [fx.url("allowed")])
        )
    }

    @Test func dryRunReportsButTouchesNothing() throws {
        let s = try setup()
        let before = s.fx.treeSnapshot()
        let result = s.remover.remove(s.findings(["allowed/a.txt", "allowed/folder"]), mode: .dryRun)

        #expect(result.removed.count == 2)
        #expect(result.failed.isEmpty)
        #expect(result.bytesFreed >= 8192)
        #expect(s.log.calls.isEmpty)
        #expect(s.fx.treeSnapshot() == before)
    }

    @Test func moveToTrashUsesInjectedTrashOnly() throws {
        let s = try setup()
        let result = s.remover.remove(s.findings(["allowed/a.txt"]), mode: .moveToTrash)

        #expect(result.removed.count == 1)
        #expect(!s.fx.exists("allowed/a.txt"))
        #expect(s.fx.exists("allowed/b.txt"))
        let trashed = try #require(result.removed.first?.trashedURL)
        #expect(trashed.path.hasPrefix(s.fx.path("FakeTrash")))
        #expect(s.log.calls == ["trash \(s.fx.path("allowed/a.txt"))"])
    }

    @Test func deletePermanentlyRemovesOnlySelectedItem() throws {
        let s = try setup()
        let result = s.remover.remove(s.findings(["allowed/folder"]), mode: .deletePermanently)

        #expect(result.removed.count == 1)
        #expect(!s.fx.exists("allowed/folder"))
        #expect(s.fx.exists("allowed/a.txt"))
        #expect(s.fx.exists("allowed/b.txt"))
        #expect(s.fx.exists("outside/secret.txt"))
    }

    @Test func refusesItemSwappedForSymlinkAfterScan() throws {
        let s = try setup()
        let findings = s.findings(["allowed/a.txt"])
        try FileManager.default.removeItem(at: s.fx.url("allowed/a.txt"))
        try s.fx.symlink("allowed/a.txt", to: s.fx.path("outside/secret.txt"))

        let result = s.remover.remove(findings, mode: .deletePermanently)
        #expect(result.removed.isEmpty)
        #expect(result.failed.count == 1)
        #expect(s.log.calls.isEmpty)
        #expect(s.fx.exists("outside/secret.txt"))
    }

    @Test func refusesDifferentFileCreatedAtScannedPath() throws {
        // A new file the user never reviewed appears at the same path. The
        // one-hour clock offset means only the identity check can catch this.
        let s = try setup()
        let findings = s.findings(["allowed/a.txt"])
        try FileManager.default.removeItem(at: s.fx.url("allowed/a.txt"))
        try s.fx.file("allowed/placeholder.txt") // keep the old inode number from being reused
        try s.fx.file("allowed/a.txt", bytes: 999)

        let result = s.remover.remove(findings, mode: .deletePermanently)
        #expect(result.removed.isEmpty)
        #expect(result.failed.first?.reason == SafetyGuard.Rejection.identityChanged.description)
        #expect(s.fx.exists("allowed/a.txt"))
    }

    @Test func refusesItemsModifiedInLastTenMinutes() throws {
        let s = try setup(clockOffset: 0)
        let result = s.remover.remove(s.findings(["allowed/a.txt"]), mode: .moveToTrash)
        #expect(result.removed.isEmpty)
        #expect(result.failed.first?.reason.contains("Modified in the last 10 minutes") == true)
        #expect(s.fx.exists("allowed/a.txt"))
    }

    @Test func refusesItemsInUse() throws {
        let s = try setup()
        let handle = try FileHandle(forReadingFrom: s.fx.url("allowed/folder/c.txt"))
        defer { try? handle.close() }

        let result = s.remover.remove(s.findings(["allowed/folder"]), mode: .deletePermanently)
        #expect(result.removed.isEmpty)
        #expect(result.failed.first?.reason == "In use by an open app")
        #expect(s.fx.exists("allowed/folder/c.txt"))
    }

    @Test func refusesForgedFindingsOutsideAllowlist() throws {
        let s = try setup()
        try s.fx.symlink("allowed/escape", to: s.fx.path("outside/secret.txt"))
        let forged = [
            Finding(category: .systemCache, target: .path(s.fx.url("outside/secret.txt")), group: "x", reclaimableBytes: 1, risk: .safe),
            Finding(category: .systemCache, target: .path(s.fx.url("allowed/escape")), group: "x", reclaimableBytes: 1, risk: .safe),
            Finding(category: .systemCache, target: .path(s.fx.url("allowed")), group: "x", reclaimableBytes: 1, risk: .safe),
            Finding(category: .systemCache, target: .path(URL(fileURLWithPath: "/System/Library")), group: "x", reclaimableBytes: 1, risk: .safe),
            Finding(category: .systemCache, target: .path(FileManager.default.homeDirectoryForCurrentUser), group: "x", reclaimableBytes: 1, risk: .safe),
        ]
        let result = s.remover.remove(forged, mode: .deletePermanently)
        #expect(result.removed.isEmpty)
        #expect(result.failed.count == forged.count)
        #expect(s.log.calls.isEmpty)
        #expect(s.fx.exists("outside/secret.txt"))
        #expect(s.fx.exists("allowed/a.txt"))
    }

    @Test func refusesAccessPlaceholdersAndCommands() throws {
        let s = try setup()
        let items = [
            Finding(category: .trash, target: .path(s.fx.url("allowed/a.txt")), group: "x",
                    reclaimableBytes: 0, risk: .review, skipReason: .needsFullDiskAccess),
            Finding(category: .xcodeJunk, target: .command(.deleteUnavailableSimulators), group: "x",
                    reclaimableBytes: 0, risk: .safe),
        ]
        let result = s.remover.remove(items, mode: .deletePermanently)
        #expect(result.removed.isEmpty)
        #expect(result.failed.count == 2)
        #expect(s.fx.exists("allowed/a.txt"))
    }

    @Test func failureDoesNotStopRemainingItems() throws {
        let s = try setup()
        let forged = Finding(category: .systemCache, target: .path(s.fx.url("outside/secret.txt")),
                             group: "x", reclaimableBytes: 1, risk: .safe)
        let result = s.remover.remove([forged] + s.findings(["allowed/b.txt"]), mode: .moveToTrash)
        #expect(result.failed.count == 1)
        #expect(result.removed.count == 1)
        #expect(!s.fx.exists("allowed/b.txt"))
        #expect(s.fx.exists("outside/secret.txt"))
    }
}
