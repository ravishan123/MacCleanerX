import Foundation
import Testing
@testable import CleanerCore

/// Every module runs against <fixture>/home and <fixture>/tmp with a fake
/// Trash and a fake command runner.
@Suite("Cleanup modules")
struct CleanupModulesTests {

    private func names(_ findings: [Finding]) -> Set<String> {
        Set(findings.map(\.displayName))
    }

    // MARK: System cache

    @Test func cachesListsTopLevelFoldersAndSkipsProtectedOnes() async throws {
        let fx = try Fixture()
        try fx.file("home/Library/Caches/com.example.editor/blob.bin", bytes: 50_000)
        try fx.file("home/Library/Caches/Homebrew/downloads/pkg.tar.gz", bytes: 80_000)
        try fx.file("home/Library/Caches/CloudKit/state.db")
        try fx.file("home/Library/Caches/com.apple.nsurlsessiond/download")
        try fx.file("home/Library/Caches/.DS_Store")
        try fx.file("home/Library/Preferences/keep.plist")

        let findings = await CachesModule(context: fx.context()).scan()

        #expect(names(findings) == ["com.example.editor", "Homebrew"])
        #expect(findings.first?.displayName == "Homebrew", "Largest first")
        #expect(findings.allSatisfy { $0.risk == .safe && $0.isSelectedByDefault })
        #expect(findings.first { $0.displayName == "Homebrew" }?.group == "Homebrew")
    }

    @Test func cachesCleanMovesOnlySelectedToTrash() async throws {
        let fx = try Fixture()
        try fx.file("home/Library/Caches/com.example.a/x", bytes: 4096)
        try fx.file("home/Library/Caches/com.example.b/y", bytes: 4096)
        let log = OperationLog()
        let module = CachesModule(context: fx.context(log: log))
        let selected = await module.scan().filter { $0.displayName == "com.example.a" }

        let result = await module.clean(selected)

        #expect(result.removed.count == 1)
        #expect(!fx.exists("home/Library/Caches/com.example.a"))
        #expect(fx.exists("home/Library/Caches/com.example.b/y"))
        #expect(fx.exists("home/Library/Caches"), "The Caches folder itself is never removed")
        #expect(log.calls.count == 1 && log.calls[0].hasPrefix("trash "))
    }

    @Test func cachesScanIsReadOnly() async throws {
        let fx = try Fixture()
        try fx.file("home/Library/Caches/com.example.a/x", bytes: 4096)
        try fx.file("home/Library/Caches/com.example.b/sub/y", bytes: 4096)
        let log = OperationLog()
        let before = fx.treeSnapshot()
        _ = await CachesModule(context: fx.context(log: log)).scan()
        #expect(fx.treeSnapshot() == before)
        #expect(log.calls.isEmpty)
    }

    // MARK: Application logs

    @Test func logsListsFoldersAndIndividualCrashReports() async throws {
        let fx = try Fixture()
        try fx.file("home/Library/Logs/com.example.app/app.log", bytes: 10_000)
        try fx.file("home/Library/Logs/install.log", bytes: 5_000)
        try fx.file("home/Library/Logs/DiagnosticReports/Editor-2026-11-01.ips", bytes: 3_000)
        try fx.file("home/Library/Logs/DiagnosticReports/Editor-2026-11-02.ips", bytes: 3_000)

        let findings = await LogsModule(context: fx.context()).scan()

        #expect(names(findings) == ["com.example.app", "install.log", "Editor-2026-11-01.ips", "Editor-2026-11-02.ips"])
        #expect(findings.filter { $0.group == LogsModule.crashReportsGroup }.count == 2)
        #expect(!names(findings).contains("DiagnosticReports"), "The crash report folder itself is not offered")
    }

    // MARK: Temporary files

    @Test func temporaryFilesSkipsSpecialFilesAndOpenFiles() async throws {
        let fx = try Fixture()
        try fx.file("tmp/old-render.tmp", bytes: 9_000)
        try fx.file("tmp/com.example.tool/cache.bin", bytes: 9_000)
        try fx.file("tmp/open.lock")
        // Special files (FIFOs, sockets) must never be offered. A FIFO is used
        // because socket paths are limited to 104 bytes, shorter than the fixture path.
        try #require(mkfifo(fx.path("tmp/agent.pipe"), 0o600) == 0)

        let handle = try FileHandle(forReadingFrom: fx.url("tmp/open.lock"))
        defer { try? handle.close() }

        let findings = await TemporaryFilesModule(context: fx.context()).scan()

        #expect(names(findings) == ["old-render.tmp", "com.example.tool", "open.lock"])
        #expect(findings.first { $0.displayName == "open.lock" }?.skipReason == .inUse)
        #expect(!names(findings).contains("agent.pipe"))
    }

    // MARK: Broken downloads

    @Test func brokenDownloadsFindsPartialFilesOnly() async throws {
        let fx = try Fixture()
        try fx.file("home/Downloads/movie.mp4.crdownload", bytes: 70_000)
        try fx.file("home/Downloads/report.pdf.part", bytes: 2_000)
        try fx.file("home/Downloads/Installer.dmg.download/Installer.dmg", bytes: 40_000)
        try fx.file("home/Downloads/Installer.dmg.download/Info.plist")
        try fx.file("home/Downloads/projects/nested/archive.zip.opdownload")
        try fx.file("home/Downloads/a/b/c/d/too-deep.crdownload")
        try fx.file("home/Downloads/finished.pdf")
        try fx.file("home/Downloads/notes.download.txt")
        try fx.file("outside/elsewhere.crdownload")
        try fx.symlink("home/Downloads/link.crdownload", to: fx.path("outside/elsewhere.crdownload"))

        let findings = await BrokenDownloadsModule(context: fx.context()).scan()

        #expect(names(findings) == [
            "movie.mp4.crdownload", "report.pdf.part", "Installer.dmg.download", "archive.zip.opdownload",
        ])
        #expect(findings.first { $0.displayName == "Installer.dmg.download" }?.group == "Safari")
        #expect(findings.first { $0.displayName == "report.pdf.part" }?.group == "Firefox")
    }

    @Test func brokenDownloadsNeverRemovesFinishedFiles() async throws {
        let fx = try Fixture()
        try fx.file("home/Downloads/movie.mp4.crdownload", bytes: 70_000)
        try fx.file("home/Downloads/finished.pdf")
        let module = BrokenDownloadsModule(context: fx.context())
        let findings = await module.scan()
        let result = await module.clean(findings, mode: .deletePermanently)
        #expect(result.removed.count == 1)
        #expect(!fx.exists("home/Downloads/movie.mp4.crdownload"))
        #expect(fx.exists("home/Downloads/finished.pdf"))
    }

    @Test func unreadableDownloadsNeedsFullDiskAccess() async throws {
        let fx = try Fixture()
        try fx.file("home/Downloads/movie.mp4.crdownload")
        let downloads = fx.path("home/Downloads")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: downloads)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: downloads) }

        let findings = await BrokenDownloadsModule(context: fx.context()).scan()
        #expect(findings.count == 1)
        #expect(findings.first?.skipReason == .needsFullDiskAccess)
    }

    // MARK: Mail attachments

    @Test func mailAttachmentsAreReviewItems() async throws {
        let fx = try Fixture()
        try fx.file("home/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/1A2B/Invoice.pdf", bytes: 30_000)
        try fx.file("home/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/3C4D/photo.jpg", bytes: 30_000)
        try fx.file("home/Library/Containers/com.apple.mail/Data/Library/Mail/V10/mailbox.emlx")

        let findings = await MailAttachmentsModule(context: fx.context()).scan()

        #expect(names(findings) == ["1A2B", "3C4D"])
        #expect(findings.allSatisfy { $0.risk == .review && !$0.isSelectedByDefault && $0.group == "Mail" })
    }

    @Test func mailCleanCannotReachMailboxes() async throws {
        let fx = try Fixture()
        try fx.file("home/Library/Containers/com.apple.mail/Data/Library/Mail/V10/mailbox.emlx")
        let module = MailAttachmentsModule(context: fx.context())
        let forged = Finding(
            category: .mailAttachments,
            target: .path(fx.url("home/Library/Containers/com.apple.mail/Data/Library/Mail")),
            group: "Mail", reclaimableBytes: 1, risk: .review
        )
        let result = await module.clean([forged], mode: .deletePermanently)
        #expect(result.removed.isEmpty)
        #expect(fx.exists("home/Library/Containers/com.apple.mail/Data/Library/Mail/V10/mailbox.emlx"))
    }

    // MARK: Xcode junk

    private func xcodeFixture() throws -> Fixture {
        let fx = try Fixture()
        try fx.file("home/Library/Developer/Xcode/DerivedData/App-abcdef/Build/out.o", bytes: 60_000)
        try fx.file("home/Library/Developer/Xcode/Archives/2026-10-01/App 1.0.xcarchive/Info.plist", bytes: 20_000)
        try fx.file("home/Library/Developer/Xcode/iOS DeviceSupport/18.0 (22A)/Symbols/dyld", bytes: 40_000)
        try fx.file("home/Library/Developer/CoreSimulator/Caches/dyld/cache.bin", bytes: 10_000)
        try fx.file("home/Library/Developer/CoreSimulator/Devices/DEAD-BEEF/data/app.db", bytes: 25_000)
        try fx.file("home/Library/Developer/Xcode/UserData/CodeSnippets/keep.codesnippet")
        return fx
    }

    private func simctlFake(_ fx: Fixture, unavailable: Bool = true) -> FakeCommands {
        let dataPath = fx.path("home/Library/Developer/CoreSimulator/Devices/DEAD-BEEF/data")
        let listing = unavailable
            ? #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-16-0":[{"udid":"DEAD-BEEF","name":"iPhone 14","dataPath":"\#(dataPath)","isAvailable":false}]}}"#
            : #"{"devices":{}}"#
        return FakeCommands([
            "simctl list devices unavailable -j": CommandOutput(status: 0, stdout: Data(listing.utf8)),
            "simctl delete unavailable": CommandOutput(status: 0, stdout: Data()),
        ])
    }

    @Test func xcodeFindsBuildProductsArchivesAndSimulators() async throws {
        let fx = try xcodeFixture()
        let commands = simctlFake(fx)
        let findings = await XcodeJunkModule(context: fx.context(commandRunner: commands.runner)).scan()

        #expect(names(findings) == ["App-abcdef", "App 1.0.xcarchive", "18.0 (22A)", "dyld", "Unavailable simulators"])
        #expect(findings.first { $0.displayName == "App 1.0.xcarchive" }?.risk == .review)
        let sims = try #require(findings.first { $0.target == .command(.deleteUnavailableSimulators) })
        #expect(sims.reclaimableBytes >= 25_000)
        #expect(sims.requiresPermanentDeletion)
        // Scanning only lists simulators; it never deletes them.
        #expect(commands.calls == [["/usr/bin/xcrun", "simctl", "list", "devices", "unavailable", "-j"]])
    }

    @Test func xcodeOmitsSimulatorsWhenNoneUnavailableOrNoXcode() async throws {
        let fx = try xcodeFixture()
        let none = await XcodeJunkModule(context: fx.context(commandRunner: simctlFake(fx, unavailable: false).runner)).scan()
        #expect(!none.contains { $0.target == .command(.deleteUnavailableSimulators) })
        let noXcode = await XcodeJunkModule(context: fx.context(commandRunner: .unavailable)).scan()
        #expect(!noXcode.contains { $0.target == .command(.deleteUnavailableSimulators) })
        #expect(noXcode.count == 4)
    }

    @Test func simulatorDeletionRunsOnlyInPermanentMode() async throws {
        let fx = try xcodeFixture()
        let commands = simctlFake(fx)
        let module = XcodeJunkModule(context: fx.context(commandRunner: commands.runner))
        let sims = await module.scan().filter { $0.target == .command(.deleteUnavailableSimulators) }
        let deleteCall = ["/usr/bin/xcrun", "simctl", "delete", "unavailable"]

        let trash = await module.clean(sims, mode: .moveToTrash)
        #expect(trash.removed.isEmpty && trash.failed.count == 1)

        let dry = await module.clean(sims, mode: .dryRun)
        #expect(dry.removed.count == 1)
        #expect(!commands.calls.contains(deleteCall))

        let real = await module.clean(sims, mode: .deletePermanently)
        #expect(real.removed.count == 1)
        #expect(commands.calls.filter { $0 == deleteCall }.count == 1)
    }

    @Test func xcodeCleanLeavesUserData() async throws {
        let fx = try xcodeFixture()
        let module = XcodeJunkModule(context: fx.context())
        let findings = await module.scan()
        let result = await module.clean(findings, mode: .moveToTrash)
        #expect(result.removed.count == 4)
        #expect(!fx.exists("home/Library/Developer/Xcode/DerivedData/App-abcdef"))
        #expect(fx.exists("home/Library/Developer/Xcode/DerivedData"))
        #expect(fx.exists("home/Library/Developer/Xcode/UserData/CodeSnippets/keep.codesnippet"))
    }

    // MARK: Cross-module rules

    @Test func exclusionsAreNeverOfferedOrRemoved() async throws {
        let fx = try Fixture()
        try fx.file("home/Library/Caches/com.example.keep/x", bytes: 4096)
        try fx.file("home/Library/Caches/com.example.drop/y", bytes: 4096)
        let excluded = fx.url("home/Library/Caches/com.example.keep")

        let plain = CachesModule(context: fx.context())
        let allFindings = await plain.scan()
        let keepFinding = try #require(allFindings.first { $0.displayName == "com.example.keep" })

        let module = CachesModule(context: fx.context(exclusions: [excluded]))
        #expect(names(await module.scan()) == ["com.example.drop"])

        // Even a finding from before the exclusion was added is refused.
        let result = await module.clean([keepFinding], mode: .deletePermanently)
        #expect(result.removed.isEmpty)
        #expect(result.failed.first?.reason == "Excluded in Settings")
        #expect(fx.exists("home/Library/Caches/com.example.keep/x"))
    }

    @Test func modulesRejectFindingsFromOtherCategories() async throws {
        let fx = try Fixture()
        try fx.file("home/Library/Caches/com.example.a/x")
        let cache = try #require(await CachesModule(context: fx.context()).scan().first)
        let result = await LogsModule(context: fx.context()).clean([cache], mode: .deletePermanently)
        #expect(result.removed.isEmpty)
        #expect(fx.exists("home/Library/Caches/com.example.a/x"))
    }

    @Test func eachModuleGuardIsScopedToItsOwnFolders() throws {
        let fx = try Fixture()
        for dir in [
            "home/Library/Caches", "home/Library/Logs", "tmp", "home/Downloads", "home/.Trash",
            "home/Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
            "home/Library/Developer/Xcode/DerivedData",
        ] { try fx.dir(dir) }
        let ctx = fx.context()
        let supports: [(String, SafetyGuard)] = [
            ("caches", PathModuleSupport(category: .systemCache, context: ctx, roots: [ctx.caches]).safetyGuard),
            ("mail", PathModuleSupport(category: .mailAttachments, context: ctx, roots: MailAttachmentsModule.roots(for: ctx)).safetyGuard),
            ("xcode", PathModuleSupport(category: .xcodeJunk, context: ctx, roots: XcodeJunkModule.roots(for: ctx)).safetyGuard),
        ]
        for (name, g) in supports {
            #expect(throws: (any Error).self, "\(name) must not reach Preferences") {
                try g.validate(fx.url("home/Library"))
            }
            #expect(throws: SafetyGuard.Rejection.homeFolder, "\(name)") { try g.validate(fx.url("home")) }
        }
    }

    @Test func standardRegistryCoversEveryCategory() throws {
        let fx = try Fixture()
        let categories = ModuleRegistry.standard(context: fx.context()).map(\.category)
        #expect(Set(categories) == Set(CleanupCategory.junkCases))
        #expect(categories.count == CleanupCategory.junkCases.count)
        let all = ModuleRegistry.all(context: fx.context()).map(\.category)
        #expect(Set(all) == Set(CleanupCategory.allCases), "Every finding can be routed to its module")
    }
}
