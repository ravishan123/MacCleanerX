import Foundation
import Testing
@testable import CleanerCore

/// The "Trash" here is always <fixture>/home/.Trash, never the real one.
@Suite("TrashModule")
struct TrashModuleTests {

    private func makeFixture() throws -> Fixture {
        let fx = try Fixture()
        try fx.file("home/.Trash/report.pdf", bytes: 20_000)
        try fx.file("home/.Trash/Old Project/main.swift", bytes: 8_000)
        try fx.file("home/.Trash/Old Project/assets/logo.png", bytes: 30_000)
        try fx.file("home/.Trash/.DS_Store", bytes: 6_148)
        try fx.file("home/Documents/keep.txt")
        try fx.file("outside/secret.txt")
        return fx
    }

    @Test func scanListsTopLevelItemsWithoutChangingAnything() async throws {
        let fx = try makeFixture()
        let log = OperationLog()
        let module = TrashModule(context: fx.context(log: log))
        let before = fx.treeSnapshot()

        let findings = await module.scan()

        #expect(fx.treeSnapshot() == before)
        #expect(log.calls.isEmpty)
        #expect(findings.count == 2, ".DS_Store is not listed")
        #expect(Set(findings.compactMap { $0.url?.lastPathComponent }) == ["report.pdf", "Old Project"])
        #expect(findings.allSatisfy { $0.risk == .review && $0.category == .trash && $0.group == "Trash" })
        #expect(findings.allSatisfy { $0.skipReason == nil && !$0.isSelectedByDefault }, "Review items start unchecked")
        #expect(findings.allSatisfy { $0.requiresPermanentDeletion })
        let folder = try #require(findings.first { $0.url?.lastPathComponent == "Old Project" })
        #expect(folder.reclaimableBytes >= 38_000)
        #expect(findings.first?.url?.lastPathComponent == "Old Project", "Sorted largest first")
    }

    @Test func recentlyModifiedItemsAreUnchecked() async throws {
        let fx = try makeFixture()
        let findings = await TrashModule(context: fx.context(clockOffset: 0)).scan()
        #expect(findings.count == 2)
        #expect(findings.allSatisfy { $0.skipReason == .recentlyModified && !$0.isSelectedByDefault })
    }

    @Test func itemsInUseAreUnchecked() async throws {
        let fx = try makeFixture()
        let handle = try FileHandle(forReadingFrom: fx.url("home/.Trash/report.pdf"))
        defer { try? handle.close() }
        let findings = await TrashModule(context: fx.context()).scan()
        let report = try #require(findings.first { $0.url?.lastPathComponent == "report.pdf" })
        #expect(report.skipReason == .inUse)
    }

    @Test func symlinkEscapingTrashIsNotListed() async throws {
        let fx = try makeFixture()
        try fx.symlink("home/.Trash/escape", to: fx.path("outside/secret.txt"))
        try fx.symlink("home/.Trash/docs", to: fx.path("home/Documents"))
        let findings = await TrashModule(context: fx.context()).scan()
        #expect(!findings.contains { ["escape", "docs"].contains($0.url?.lastPathComponent) })
    }

    @Test func moveToTrashModeIsRefused() async throws {
        let fx = try makeFixture()
        let log = OperationLog()
        let module = TrashModule(context: fx.context(log: log))
        let findings = await module.scan()
        let before = fx.treeSnapshot()

        let result = await module.clean(findings) // default mode is .moveToTrash

        #expect(result.removed.isEmpty)
        #expect(result.failed.count == findings.count)
        #expect(result.failed.allSatisfy { $0.reason.contains("Delete permanently") })
        #expect(log.calls.isEmpty)
        #expect(fx.treeSnapshot() == before)
    }

    @Test func deletePermanentlyRemovesOnlySelectedItems() async throws {
        let fx = try makeFixture()
        let log = OperationLog()
        let module = TrashModule(context: fx.context(log: log))
        let selected = await module.scan().filter { $0.url?.lastPathComponent == "report.pdf" }

        let result = await module.clean(selected, mode: .deletePermanently)

        #expect(result.removed.count == 1)
        #expect(result.bytesFreed >= 20_000)
        #expect(!fx.exists("home/.Trash/report.pdf"))
        #expect(fx.exists("home/.Trash/Old Project/main.swift"))
        #expect(fx.exists("home/.Trash/.DS_Store"))
        #expect(fx.exists("home/Documents/keep.txt"))
        #expect(log.calls == ["delete \(fx.path("home/.Trash/report.pdf"))"])
    }

    @Test func dryRunReportsSpaceWithoutDeleting() async throws {
        let fx = try makeFixture()
        let log = OperationLog()
        let module = TrashModule(context: fx.context(log: log))
        let findings = await module.scan()
        let before = fx.treeSnapshot()

        let result = await module.clean(findings, mode: .dryRun)

        #expect(result.removed.count == 2)
        #expect(result.bytesFreed >= 58_000)
        #expect(log.calls.isEmpty)
        #expect(fx.treeSnapshot() == before)
    }

    @Test func unreadableTrashReportsNeedsFullDiskAccess() async throws {
        let fx = try makeFixture()
        let trash = fx.path("home/.Trash")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: trash)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: trash) }

        let module = TrashModule(context: fx.context())
        let findings = await module.scan()

        #expect(findings.count == 1)
        #expect(findings.first?.skipReason == .needsFullDiskAccess)
        #expect(findings.first?.reclaimableBytes == 0)

        let result = await module.clean(findings, mode: .deletePermanently)
        #expect(result.removed.isEmpty)
        #expect(result.failed.count == 1)
    }

    @Test func missingTrashFolderYieldsNoFindings() async throws {
        let fx = try Fixture()
        try fx.dir("home")
        #expect(await TrashModule(context: fx.context()).scan().isEmpty)
    }

    @Test func refusesFindingsFromOtherModules() async throws {
        let fx = try makeFixture()
        let module = TrashModule(context: fx.context())
        var findings = await module.scan()
        let foreign = try #require(findings.first)
        findings = [Finding(category: .systemCache, target: foreign.target, group: "x",
                            reclaimableBytes: 1, risk: .safe, scannedIdentity: foreign.scannedIdentity)]
        let result = await module.clean(findings, mode: .deletePermanently)
        #expect(result.removed.isEmpty)
        #expect(fx.exists("home/.Trash/" + (foreign.url?.lastPathComponent ?? "")))
    }

    @Test func guardIsScopedToTrash() throws {
        let fx = try makeFixture()
        let module = TrashModule(context: fx.context())
        #expect(module.safetyGuard.allowedRoots.map(\.path) == [fx.path("home/.Trash")])
        #expect(throws: SafetyGuard.Rejection.outsideAllowlist) {
            try module.safetyGuard.validate(fx.url("home/Documents/keep.txt"))
        }
        #expect(throws: SafetyGuard.Rejection.homeFolder) {
            try module.safetyGuard.validate(fx.url("home"))
        }
    }
}
