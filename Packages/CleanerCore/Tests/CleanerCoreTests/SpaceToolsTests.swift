import Darwin
import Foundation
import Testing
@testable import CleanerCore

private func names(_ findings: [Finding]) -> Set<String> { Set(findings.map(\.displayName)) }

private func randomData(_ count: Int) -> Data {
    var g = SystemRandomNumberGenerator()
    return Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &g) })
}

/// Sets both the access and modification time.
private func age(_ fx: Fixture, _ relative: String, days: Double) {
    let seconds = Date().addingTimeInterval(-days * 86_400).timeIntervalSince1970
    var times = [timeval(tv_sec: Int(seconds), tv_usec: 0), timeval(tv_sec: Int(seconds), tv_usec: 0)]
    _ = utimes(fx.path(relative), &times)
}

@Suite("Extra cleanup categories")
struct ExtraJunkTests {

    @Test func developerCachesOfferOnlyCacheFolders() async throws {
        let fx = try Fixture()
        try fx.file("home/.npm/_cacache/index/abc", bytes: 9_000)
        try fx.file("home/.npm/_logs/debug.log")
        try fx.file("home/.gradle/caches/modules/x.jar", bytes: 9_000)
        try fx.file("home/.gradle/gradle.properties")
        try fx.file("home/.m2/repository/org/x.jar", bytes: 9_000)
        let findings = await DeveloperCachesModule(context: fx.context()).scan()

        #expect(names(findings) == ["_cacache", "caches", "repository"])
        #expect(findings.first { $0.group == "Maven" }?.risk == .review)
        #expect(findings.first { $0.group == "npm" }?.risk == .safe)

        let result = await DeveloperCachesModule(context: fx.context()).clean(findings, mode: .deletePermanently)
        #expect(result.removed.count == 3)
        #expect(fx.exists("home/.npm/_logs/debug.log"))
        #expect(fx.exists("home/.gradle/gradle.properties"))
        #expect(fx.exists("home/.npm"), "Parent folders stay")
    }

    @Test func iosUpdatesAndBackups() async throws {
        let fx = try Fixture()
        try fx.file("home/Library/iTunes/iPhone Software Updates/iPhone_18.0_Restore.ipsw", bytes: 50_000)
        try fx.file("home/Library/iTunes/iPhone Software Updates/notes.txt")
        try fx.file("home/Library/Application Support/MobileSync/Backup/00008110-ABC/Manifest.db", bytes: 40_000)
        let info = try PropertyListSerialization.data(fromPropertyList: ["Device Name": "Test iPhone"], format: .xml, options: 0)
        try info.write(to: fx.url("home/Library/Application Support/MobileSync/Backup/00008110-ABC/Info.plist"))

        let updates = await IOSUpdatesModule(context: fx.context()).scan()
        #expect(names(updates) == ["iPhone_18.0_Restore.ipsw"])
        #expect(updates.first?.risk == .safe)

        let backups = await IOSBackupsModule(context: fx.context()).scan()
        #expect(backups.count == 1)
        #expect(backups.first?.group == "Test iPhone")
        #expect(backups.first?.risk == .review)
        #expect(backups.first?.isSelectedByDefault == false)
    }

    @Test func installersOlderThanAWeekOnly() async throws {
        let fx = try Fixture()
        try fx.file("home/Downloads/Old.dmg", bytes: 20_000)
        try fx.file("home/Downloads/Old.pkg", bytes: 20_000)
        try fx.file("home/Downloads/New.dmg", bytes: 20_000)
        try fx.file("home/Downloads/Report.pdf", bytes: 20_000)
        age(fx, "home/Downloads/Old.dmg", days: 30)
        age(fx, "home/Downloads/Old.pkg", days: 30)
        age(fx, "home/Downloads/Report.pdf", days: 30)

        let findings = await InstallersModule(context: fx.context()).scan()
        #expect(names(findings) == ["Old.dmg", "Old.pkg"])
        #expect(findings.allSatisfy { $0.risk == .review })
        #expect(Set(findings.map(\.group)) == ["Disk images", "Installer packages"])
    }

    @Test func brokenStartupItemsOnly() async throws {
        let fx = try Fixture()
        try fx.dir("home/Library/LaunchAgents")
        func plist(_ name: String, _ dict: [String: Any]) throws {
            try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
                .write(to: fx.url("home/Library/LaunchAgents/\(name)"))
        }
        try plist("com.example.gone.plist", ["Label": "com.example.gone", "Program": fx.path("nope/agent")])
        try plist("com.example.ok.plist", ["Label": "com.example.ok", "Program": "/bin/ls"])
        try plist("com.apple.thing.plist", ["Label": "com.apple.thing", "Program": fx.path("nope/x")])
        try plist("com.example.bundled.plist", ["Label": "com.example.bundled", "BundleProgram": "Contents/MacOS/x"])

        let findings = await BrokenStartupItemsModule(context: fx.context()).scan()
        #expect(names(findings) == ["com.example.gone.plist"])
        #expect(findings.first?.risk == .review)
    }
}

@Suite("Storage overview")
struct StorageTests {

    @Test func classifierUsesLocationThenFileType() {
        let c = StorageClassifier(homeComponents: 2) // /Users/me
        #expect(c.classify("/Users/me/Documents/report.pdf").0 == .documents)
        #expect(c.classify("/Users/me/Pictures/a.jpg").0 == .images)
        #expect(c.classify("/Users/me/Movies/b.mov").0 == .videos)
        #expect(c.classify("/Users/me/Music/c.mp3").0 == .audio)
        #expect(c.classify("/Users/me/Downloads/d.zip").0 == .archives)
        #expect(c.classify("/Users/me/Downloads/e.dmg").0 == .archives)
        #expect(c.classify("/Users/me/code/main.swift").0 == .developer)
        #expect(c.classify("/Users/me/notes.unknownext").0 == .other)

        #expect(c.classify("/Users/me/Library/Caches/com.x/blob") == (.cachesAndLogs, "/Users/me/Library/Caches/com.x"))
        #expect(c.classify("/Users/me/Library/Logs/app.log").0 == .cachesAndLogs)
        #expect(c.classify("/Users/me/Library/Mail/V10/a.emlx").0 == .mail)
        #expect(c.classify("/Users/me/Library/Containers/com.apple.mail/Data/x").0 == .mail)
        #expect(c.classify("/Users/me/Library/Application Support/MobileSync/Backup/ABC/f")
                == (.iosBackups, "/Users/me/Library/Application Support/MobileSync/Backup/ABC"))
        #expect(c.classify("/Users/me/Library/Application Support/Foo/db").0 == .appData)
        #expect(c.classify("/Users/me/Library/Developer/Xcode/DerivedData/x").0 == .developer)
        #expect(c.classify("/Users/me/.Trash/old.pdf") == (.trash, "/Users/me/.Trash/old.pdf"))
        #expect(c.classify("/Users/me/.npm/_cacache/x") == (.developer, "/Users/me/.npm"))
        #expect(c.classify("/Users/me/web/node_modules/react/index.js") == (.developer, "/Users/me/web/node_modules"))
        #expect(c.classify("/Users/me/Pictures/Photos Library.photoslibrary/originals/1.heic")
                == (.images, "/Users/me/Pictures/Photos Library.photoslibrary"))
        #expect(c.classify("/Users/me/Applications/Tool.app/Contents/MacOS/Tool") == (.apps, "/Users/me/Applications/Tool.app"))
    }

    @Test func scannerTotalsCategoriesWithoutChangingAnything() async throws {
        let fx = try Fixture()
        try fx.file("home/Documents/report.pdf", bytes: 2_000_000)
        try fx.file("home/Pictures/a.jpg", bytes: 300_000)
        try fx.file("home/Movies/b.mov", bytes: 3_000_000)
        try fx.file("home/Music/c.mp3", bytes: 400_000)
        try fx.file("home/Library/Caches/com.example.x/blob", bytes: 500_000)
        try fx.file("home/Library/Caches/com.example.x/blob2", bytes: 700_000)
        try fx.file("home/.Trash/old.zip", bytes: 100_000)
        try fx.file("Apps/Tool.app/Contents/MacOS/Tool", bytes: 1_500_000)
        let before = fx.treeSnapshot()

        let scanner = StorageScanner(home: fx.url("home"), applicationFolders: [fx.url("Apps")])
        let report = await scanner.scan()

        #expect(fx.treeSnapshot() == before)
        #expect(report.bytes(.documents) >= 2_000_000)
        #expect(report.bytes(.videos) >= 3_000_000)
        #expect(report.bytes(.images) >= 300_000)
        #expect(report.bytes(.audio) >= 400_000)
        #expect(report.bytes(.trash) >= 100_000)
        #expect(report.bytes(.apps) >= 1_500_000)
        let caches = try #require(report.usage[.cachesAndLogs])
        #expect(caches.bytes >= 1_200_000)
        #expect(caches.largest.first?.url.lastPathComponent == "com.example.x", "Cache files roll up to their app folder")
        #expect(report.usage[.videos]?.largest.first?.url.lastPathComponent == "b.mov")
        #expect(report.sortedCategories.first == .videos)
        #expect(report.volumeTotal > 0)
    }
}

@Suite("Large & old files")
struct LargeOldFilesTests {

    @Test func findsLargeAndOldFilesInPersonalFoldersOnly() async throws {
        let fx = try Fixture()
        try fx.file("home/Movies/big.mov", bytes: 3_000_000)
        try fx.file("home/Documents/small-new.txt", bytes: 1_500_000)
        try fx.file("home/Documents/old.pdf", bytes: 1_500_000)
        try fx.file("home/Documents/tiny-old.txt", bytes: 100)
        try fx.file("home/Documents/.hidden-big", bytes: 3_000_000)
        try fx.file("home/Pictures/Photos Library.photoslibrary/originals/huge.heic", bytes: 3_000_000)
        try fx.file("home/Library/Caches/huge.bin", bytes: 3_000_000)
        age(fx, "home/Documents/old.pdf", days: 400)
        age(fx, "home/Documents/tiny-old.txt", days: 400)

        let criteria = LargeOldFilesModule.Criteria(minimumBytes: 2_000_000, unusedFor: 365 * 86_400, oldMinimumBytes: 1_000_000)
        let findings = await LargeOldFilesModule(context: fx.context(), criteria: criteria).scan()

        #expect(names(findings) == ["big.mov", "old.pdf"])
        #expect(findings.allSatisfy { $0.risk == .review && !$0.isSelectedByDefault })
        #expect(findings.first { $0.displayName == "big.mov" }?.group == "Videos")
        let old = try #require(findings.first { $0.displayName == "old.pdf" })
        #expect(old.lastOpened.map { $0 < Date().addingTimeInterval(-300 * 86_400) } == true)
    }

    @Test func cleaningGoesToTrashAndStaysInPersonalFolders() async throws {
        let fx = try Fixture()
        try fx.file("home/Movies/big.mov", bytes: 3_000_000)
        try fx.file("home/Library/Preferences/keep.plist")
        let log = OperationLog()
        let module = LargeOldFilesModule(context: fx.context(log: log), criteria: .init(minimumBytes: 2_000_000))
        let findings = await module.scan()
        let forged = Finding(category: .largeOldFiles, target: .path(fx.url("home/Library/Preferences/keep.plist")),
                             group: "x", reclaimableBytes: 1, risk: .review)

        let result = await module.clean(findings + [forged], mode: .moveToTrash)
        #expect(result.removed.count == 1)
        #expect(result.failed.count == 1)
        #expect(!fx.exists("home/Movies/big.mov"))
        #expect(fx.exists("home/Library/Preferences/keep.plist"))
        #expect(log.calls.allSatisfy { $0.hasPrefix("trash ") })
    }
}

@Suite("Duplicates")
struct DuplicatesTests {

    private func makeFixture() throws -> Fixture {
        let fx = try Fixture()
        let a = randomData(2_000_000)
        try fx.dir("home/Documents"); try fx.dir("home/Downloads"); try fx.dir("home/Desktop")
        try a.write(to: fx.url("home/Documents/a.bin"))
        try a.write(to: fx.url("home/Downloads/a copy.bin"))
        try a.write(to: fx.url("home/Desktop/a again.bin"))
        // Same size, same first and last 64 KB, different middle: not a duplicate.
        var b = a
        b[1_000_000] ^= 0xFF
        try b.write(to: fx.url("home/Documents/b.bin"))
        // A hard link is the same file, not a copy.
        try FileManager.default.linkItem(at: fx.url("home/Documents/a.bin"), to: fx.url("home/Documents/a-link.bin"))
        return fx
    }

    @Test func findsExactCopiesOnly() async throws {
        let fx = try makeFixture()
        let before = fx.treeSnapshot()
        let findings = await DuplicatesModule(context: fx.context()).scan()

        #expect(fx.treeSnapshot() == before)
        #expect(Set(findings.compactMap(\.duplicateSet)).count == 1)
        let paths = Set(findings.map(\.displayName))
        #expect(paths.count == 3)
        #expect(paths.isSubset(of: ["a.bin", "a-link.bin", "a copy.bin", "a again.bin"]))
        #expect(!paths.contains("b.bin"))
        #expect(paths.contains("a copy.bin") && paths.contains("a again.bin"))
        #expect(findings.allSatisfy { $0.relatedPaths.count == 2 && $0.risk == .review && !$0.isSelectedByDefault })
    }

    @Test func neverRemovesTheLastCopy() async throws {
        let fx = try makeFixture()
        let log = OperationLog()
        let module = DuplicatesModule(context: fx.context(log: log))
        let findings = await module.scan()

        let all = await module.clean(findings, mode: .deletePermanently)
        #expect(all.removed.isEmpty)
        #expect(all.failed.count == 3)
        #expect(all.failed.allSatisfy { $0.reason == "No other identical copy would remain" })
        #expect(log.calls.isEmpty)

        let someCopies = findings.filter { $0.displayName != "a copy.bin" }
        let result = await module.clean(someCopies, mode: .moveToTrash)
        #expect(result.removed.count == 2)
        #expect(fx.exists("home/Downloads/a copy.bin"))
    }

    @Test func refusesWhenTheKeptCopyChanged() async throws {
        let fx = try makeFixture()
        let module = DuplicatesModule(context: fx.context())
        let findings = await module.scan()
        let keep = "a copy.bin"
        // After the scan, the copy we were going to keep is edited.
        try randomData(2_000_000).write(to: fx.url("home/Downloads/\(keep)"))
        let others = findings.filter { $0.displayName != keep }
        // The other kept-candidates are being removed too, so nothing identical remains.
        let result = await module.clean(others, mode: .deletePermanently)
        #expect(result.removed.isEmpty)
        #expect(others.allSatisfy { f in fx.exists(String(f.displayPath.dropFirst(fx.root.path.count + 1))) })
    }

    @Test func clonesAreReportedButFreeNothing() async throws {
        let fx = try Fixture()
        try fx.dir("home/Documents")
        try randomData(2_000_000).write(to: fx.url("home/Documents/original.bin"))
        try #require(clonefile(fx.path("home/Documents/original.bin"), fx.path("home/Documents/clone.bin"), 0) == 0)
        let findings = await DuplicatesModule(context: fx.context()).scan()
        #expect(findings.count == 2)
        #expect(findings.allSatisfy { $0.reclaimableBytes < 500_000 })
    }
}

@Suite("App uninstaller")
struct AppUninstallerTests {

    private func makeApp(_ fx: Fixture, _ relative: String, bundleID: String) throws {
        try fx.dir("\(relative)/Contents/MacOS")
        let info: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleName": URL(fileURLWithPath: relative).deletingPathExtension().lastPathComponent,
                                   "CFBundleExecutable": "main", "CFBundleShortVersionString": "1.0"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: fx.url("\(relative)/Contents/Info.plist"))
        try fx.file("\(relative)/Contents/MacOS/main", bytes: 50_000)
    }

    private func guardFor(_ fx: Fixture) -> AppBundleGuard {
        AppBundleGuard(applicationFolders: [fx.url("Applications")])
    }

    @Test func guardAllowsOnlyOwnedTopLevelApps() throws {
        let fx = try Fixture()
        try makeApp(fx, "Applications/Foo.app", bundleID: "com.example.foo")
        try makeApp(fx, "Applications/Tools/Bar.app", bundleID: "com.example.bar")
        try makeApp(fx, "Applications/Deep/More/Baz.app", bundleID: "com.example.baz")
        try makeApp(fx, "Applications/Store.app", bundleID: "com.example.store")
        try fx.file("Applications/Store.app/Contents/_MASReceipt/receipt")
        try makeApp(fx, "Applications/Mac Cleaner.app", bundleID: "io.github.maccleaner.app")
        try makeApp(fx, "Elsewhere/Out.app", bundleID: "com.example.out")
        try fx.symlink("Applications/Link.app", to: fx.path("Elsewhere/Out.app"))
        let g = guardFor(fx)

        #expect(throws: Never.self) { try g.validate(fx.url("Applications/Foo.app"), running: []) }
        #expect(throws: Never.self) { try g.validate(fx.url("Applications/Tools/Bar.app"), running: []) }
        #expect(throws: AppBundleGuard.Rejection.notInApplicationsFolder) { try g.validate(fx.url("Applications/Deep/More/Baz.app"), running: []) }
        #expect(throws: AppBundleGuard.Rejection.appStoreApp) { try g.validate(fx.url("Applications/Store.app"), running: []) }
        #expect(throws: AppBundleGuard.Rejection.protectedApp) { try g.validate(fx.url("Applications/Mac Cleaner.app"), running: []) }
        #expect(throws: AppBundleGuard.Rejection.notInApplicationsFolder) { try g.validate(fx.url("Elsewhere/Out.app"), running: []) }
        #expect(throws: AppBundleGuard.Rejection.symlink) { try g.validate(fx.url("Applications/Link.app"), running: []) }
        #expect(throws: AppBundleGuard.Rejection.notInApplicationsFolder) {
            try g.validate(URL(fileURLWithPath: fx.path("Applications") + "/../Elsewhere/Out.app"), running: [])
        }
        #expect(throws: AppBundleGuard.Rejection.running) {
            try g.validate(fx.url("Applications/Foo.app"), running: [fx.path("Applications/Foo.app/Contents/MacOS/main")])
        }
        #expect(throws: AppBundleGuard.Rejection.notAnApp) { try g.validate(fx.url("Applications/Foo.app/Contents"), running: []) }
    }

    @Test func guardRefusesAppleAppsAndReadOnlyFolders() throws {
        let fx = try Fixture()
        let apple = AppBundleGuard(applicationFolders: [URL(fileURLWithPath: "/System/Applications")])
        #expect(throws: (any Error).self) {
            try apple.validate(URL(fileURLWithPath: "/System/Applications/Calculator.app"), running: [])
        }

        try makeApp(fx, "Applications/Foo.app", bundleID: "com.example.foo")
        let folder = fx.path("Applications")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder) }
        #expect(throws: AppBundleGuard.Rejection.folderNotWritable) { try guardFor(fx).validate(fx.url("Applications/Foo.app"), running: []) }
    }

    @Test func inventoryListsAppsWithReasons() throws {
        let fx = try Fixture()
        try makeApp(fx, "Applications/Foo.app", bundleID: "com.example.foo")
        try makeApp(fx, "Applications/Tools/Bar.app", bundleID: "com.example.bar")
        try makeApp(fx, "Applications/Deep/More/Baz.app", bundleID: "com.example.baz")
        try makeApp(fx, "Applications/Store.app", bundleID: "com.example.store")
        try fx.file("Applications/Store.app/Contents/_MASReceipt/receipt")

        let apps = AppInventory.apps(in: [fx.url("Applications")], appGuard: guardFor(fx))
        #expect(apps.map(\.name) == ["Bar", "Foo", "Store"])
        #expect(apps.first { $0.name == "Foo" }?.canUninstall == true)
        #expect(apps.first { $0.name == "Store" }?.isAppStore == true)
        #expect(apps.first { $0.name == "Store" }?.canUninstall == false)
    }

    private func leftoverFixture() throws -> (Fixture, InstalledApp, [InstalledApp]) {
        let fx = try Fixture()
        try makeApp(fx, "Applications/Foo.app", bundleID: "com.example.foo")
        try fx.file("home/Library/Application Support/com.example.foo/data.db", bytes: 10_000)
        try fx.file("home/Library/Application Support/Foo/settings.json")
        try fx.file("home/Library/Caches/com.example.foo/cache.bin", bytes: 10_000)
        try fx.file("home/Library/Preferences/com.example.foo.plist")
        try fx.file("home/Library/Saved Application State/com.example.foo.savedState/window.data")
        try fx.file("home/Library/LaunchAgents/com.example.foo.helper.plist")
        try fx.file("home/Library/Group Containers/TEAM1.com.example.shared/x")
        try fx.file("home/Library/Preferences/com.example.other.plist")
        try fx.file("home/Library/Application Support/Other/keep")
        let foo = InstalledApp(url: fx.url("Applications/Foo.app"), name: "Foo", bundleID: "com.example.foo", version: "1.0",
                               teamID: "TEAM1", signature: .unsigned, isAppStore: false, isOwnedByUser: true, sizeBytes: nil, blockReason: nil)
        let other = InstalledApp(url: fx.url("Applications/Other.app"), name: "Other", bundleID: "com.example.other", version: nil,
                                 teamID: "TEAM2", signature: .unsigned, isAppStore: false, isOwnedByUser: true, sizeBytes: nil, blockReason: nil)
        return (fx, foo, [foo, other])
    }

    @Test func planFindsAppAndItsLeftoversOnly() throws {
        let (fx, foo, apps) = try leftoverFixture()
        let module = AppUninstallModule(context: fx.context(), applicationFolders: [fx.url("Applications")], runningApps: { [] })
        let plan = module.plan(for: foo, otherApps: apps)
        let byName = Dictionary(plan.map { ($0.displayName, $0) }, uniquingKeysWith: { a, _ in a })

        #expect(Set(byName.keys) == [
            "Foo.app", "com.example.foo", "Foo", "com.example.foo.plist", "com.example.foo.savedState",
            "com.example.foo.helper.plist", "TEAM1.com.example.shared",
        ])
        #expect(byName["Foo.app"]?.group == "Application")
        #expect(byName["Foo"]?.risk == .review, "Name-only matches are Review")
        #expect(plan.filter { $0.displayName == "com.example.foo" }.count == 2, "Application Support and Caches")
        #expect(plan.first { $0.group == "Caches" }?.risk == .safe)
        #expect(byName["TEAM1.com.example.shared"]?.risk == .review)
        #expect(byName["com.example.other.plist"] == nil)
    }

    @Test func sharedTeamContainersAreNotOffered() throws {
        let (fx, foo, _) = try leftoverFixture()
        let sibling = InstalledApp(url: fx.url("Applications/Sibling.app"), name: "Sibling", bundleID: "com.example.sibling", version: nil,
                                   teamID: "TEAM1", signature: .unsigned, isAppStore: false, isOwnedByUser: true, sizeBytes: nil, blockReason: nil)
        let module = AppUninstallModule(context: fx.context(), applicationFolders: [fx.url("Applications")], runningApps: { [] })
        let plan = module.plan(for: foo, otherApps: [foo, sibling])
        #expect(!plan.contains { $0.displayName == "TEAM1.com.example.shared" })
    }

    @Test func uninstallMovesAppToTrashAndNeverDeletesItPermanently() async throws {
        let (fx, foo, apps) = try leftoverFixture()
        let log = OperationLog()
        let module = AppUninstallModule(context: fx.context(log: log), applicationFolders: [fx.url("Applications")], runningApps: { [] })
        let plan = module.plan(for: foo, otherApps: apps)
        let app = plan.filter { $0.group == "Application" }

        let permanent = await module.clean(app, mode: .deletePermanently)
        #expect(permanent.removed.isEmpty)
        #expect(permanent.failed.first?.reason == "Apps always go to the Trash")
        #expect(fx.exists("Applications/Foo.app"))

        let dry = await module.clean(plan, mode: .dryRun)
        #expect(dry.removed.count == plan.count)
        #expect(log.calls.isEmpty)

        let real = await module.clean(plan, mode: .moveToTrash)
        #expect(real.failed.isEmpty)
        #expect(!fx.exists("Applications/Foo.app"))
        #expect(!fx.exists("home/Library/Preferences/com.example.foo.plist"))
        #expect(fx.exists("home/Library/Preferences/com.example.other.plist"))
        #expect(fx.exists("home/Library/Application Support/Other/keep"))
        #expect(log.calls.allSatisfy { $0.hasPrefix("trash ") })
    }

    @Test func uninstallRefusesAppThatStartedRunning() async throws {
        let (fx, foo, apps) = try leftoverFixture()
        let running = fx.path("Applications/Foo.app/Contents/MacOS/main")
        let planner = AppUninstallModule(context: fx.context(), applicationFolders: [fx.url("Applications")], runningApps: { [] })
        let app = planner.plan(for: foo, otherApps: apps).filter { $0.group == "Application" }
        let module = AppUninstallModule(context: fx.context(), applicationFolders: [fx.url("Applications")], runningApps: { [running] })
        let result = await module.clean(app, mode: .moveToTrash)
        #expect(result.removed.isEmpty)
        #expect(fx.exists("Applications/Foo.app"))
    }

    @Test func leftoversOfDeletedAppsOnly() async throws {
        let fx = try Fixture()
        try fx.file("home/Library/Preferences/com.gone.app.plist")
        try fx.file("home/Library/Application Support/com.gone.app/db", bytes: 5_000)
        try fx.file("home/Library/Application Support/com.installed.app.helper/db")
        try fx.file("home/Library/Preferences/com.apple.finder.plist")
        try fx.file("home/Library/Application Support/Some Folder/db")
        try fx.file("home/Library/Saved Application State/com.gone.app.savedState/x")

        let module = AppLeftoversModule(context: fx.context(), isInstalled: { $0 == "com.installed.app" })
        let findings = await module.scan()
        #expect(names(findings) == ["com.gone.app.plist", "com.gone.app", "com.gone.app.savedState"])
        #expect(findings.allSatisfy { $0.group == "com.gone.app" && $0.risk == .review })
    }

    @Test func bundleIDParsing() {
        #expect(AppLeftoversModule.bundleID(fromName: "com.example.App.plist") == "com.example.App")
        #expect(AppLeftoversModule.bundleID(fromName: "com.example.App.savedState") == "com.example.App")
        #expect(AppLeftoversModule.bundleID(fromName: "Google") == nil)
        #expect(AppLeftoversModule.bundleID(fromName: "com.apple.Safari.plist") == nil)
        #expect(AppLeftoversModule.bundleID(fromName: "group.com.example.shared") == nil)
        #expect(AppLeftoversModule.bundleID(fromName: "My Folder.with.dots") == nil)
    }
}
