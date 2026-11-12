import Foundation

/// Something the security scan wants the user to look at. These are
/// heuristics, not malware signatures, so nothing here is removed
/// automatically.
public struct SecurityFinding: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable {
        case launchItem, application
    }

    public enum Severity: Int, Sendable, Hashable, Comparable {
        /// Worth a look, usually harmless (unsigned tool, leftover item).
        case review = 1
        /// Matches patterns commonly used by malware.
        case suspicious = 2

        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    public var id: String { path.path(percentEncoded: false) }
    public let kind: Kind
    public let path: URL
    public let title: String
    public let reasons: [String]
    public let severity: Severity
    public let signature: SignatureStatus?
}

public struct SecurityReport: Sendable, Hashable {
    public let findings: [SecurityFinding]
    public let launchItemsChecked: Int
    public let appsChecked: Int

    public var suspicious: [SecurityFinding] { findings.filter { $0.severity == .suspicious } }
    public var threatCount: Int { suspicious.count }

    /// Honest wording: we can only say no *known* threat patterns were found.
    public var headline: String {
        threatCount == 0 ? "No known threats found" : "\(threatCount) suspicious item\(threatCount == 1 ? "" : "s") found"
    }

    public static let disclaimer =
        "Mac Cleaner checks startup items and app signatures for common warning signs. It is not antivirus software and cannot guarantee your Mac is free of malware."
}

public struct SecurityScanner: Sendable {
    public var launchFolders: [(URL, LaunchItem.Scope)]
    public var appFolders: [URL]
    public var commandRunner: CommandRunner
    /// Bundle identifiers never flagged (Mac Cleaner itself is ad-hoc signed).
    public var trustedBundleIDs: Set<String>
    public var maxConcurrentChecks = 6
    /// Programs started from these folders are treated as suspicious.
    public var suspiciousLocations = SecurityScanner.temporaryPrefixes

    public init(
        launchFolders: [(URL, LaunchItem.Scope)],
        appFolders: [URL],
        commandRunner: CommandRunner,
        trustedBundleIDs: Set<String> = ["io.github.maccleaner.app"]
    ) {
        self.launchFolders = launchFolders
        self.appFolders = appFolders
        self.commandRunner = commandRunner
        self.trustedBundleIDs = trustedBundleIDs
    }

    public static func live(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> SecurityScanner {
        SecurityScanner(
            launchFolders: LaunchItemInventory.standardFolders(home: home),
            appFolders: [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                home.appending(path: "Applications", directoryHint: .isDirectory),
                home.appending(path: "Downloads", directoryHint: .isDirectory),
            ],
            commandRunner: .live
        )
    }

    public func scan() async -> SecurityReport {
        let items = LaunchItemInventory.items(in: launchFolders)
        let apps = appFolders.flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "app" }
        }

        var findings = items.compactMap { Self.evaluate($0, suspiciousLocations: suspiciousLocations) }
        findings += await evaluateApps(apps)
        findings.sort { ($0.severity, $1.title) > ($1.severity, $0.title) }
        return SecurityReport(findings: findings, launchItemsChecked: items.count, appsChecked: apps.count)
    }

    // MARK: Launch items

    static let interpreters: Set<String> = [
        "sh", "bash", "zsh", "dash", "ksh", "csh", "tcsh", "python", "python3", "perl", "ruby", "osascript", "node",
    ]
    static let downloaderPatterns = ["curl ", "wget ", "base64", "| sh", "|sh", "| bash", "|bash", "eval ", "http://", "https://", "osascript -e"]
    static let temporaryPrefixes = ["/tmp/", "/private/tmp/", "/var/tmp/", "/private/var/tmp/", "/private/var/folders/", "/var/folders/", "/Users/Shared/"]

    static func evaluate(_ item: LaunchItem, suspiciousLocations: [String] = temporaryPrefixes) -> SecurityFinding? {
        guard !item.isApple else { return nil }
        var suspicious: [String] = []
        var review: [String] = []
        var signature: SignatureStatus?

        if !item.isReadable {
            review.append("The startup item file can't be read.")
        }
        if item.isHidden {
            suspicious.append("The startup item is hidden.")
        }

        if let rawProgram = item.program, !item.isBundleProgram {
            let program = LaunchItemInventory.resolveProgram(rawProgram)
            let name = URL(fileURLWithPath: program).lastPathComponent
            let inspected = interpreters.contains(name) ? item.arguments.dropFirst().first { $0.hasPrefix("/") } : program

            if interpreters.contains(name) {
                let commandLine = item.arguments.dropFirst().joined(separator: " ")
                if downloaderPatterns.contains(where: commandLine.contains) {
                    suspicious.append("Runs an inline script that downloads or decodes code.")
                } else {
                    review.append("Runs a script with \(name).")
                }
            }

            if let target = inspected {
                if suspiciousLocations.contains(where: target.hasPrefix) {
                    suspicious.append("Runs a program from a temporary or shared folder.")
                } else if target.split(separator: "/").dropLast().contains(where: { $0.hasPrefix(".") }) {
                    review.append("Runs a program from a hidden folder.")
                }

                if !FileManager.default.fileExists(atPath: target) {
                    review.append("Points to a program that no longer exists.")
                } else if !interpreters.contains(name) || target != program {
                    let status = SignatureChecker.status(of: URL(fileURLWithPath: target))
                    signature = status
                    switch status {
                    case .invalid: suspicious.append("The program's code signature is broken.")
                    case .unsigned: review.append("The program is not signed.")
                    default: break
                    }
                }
            }
        }

        guard !suspicious.isEmpty || !review.isEmpty else { return nil }
        return SecurityFinding(
            kind: .launchItem,
            path: item.plist,
            title: item.displayName,
            reasons: suspicious + review,
            severity: suspicious.isEmpty ? .review : .suspicious,
            signature: signature
        )
    }

    // MARK: Applications

    private func evaluateApps(_ apps: [URL]) async -> [SecurityFinding] {
        await withTaskGroup(of: SecurityFinding?.self) { group in
            var results: [SecurityFinding] = []
            var iterator = apps.makeIterator()
            func addNext() -> Bool {
                guard let app = iterator.next() else { return false }
                group.addTask { await evaluateApp(app) }
                return true
            }
            for _ in 0..<maxConcurrentChecks where !addNext() { break }
            while let finding = await group.next() {
                if let finding { results.append(finding) }
                _ = addNext()
            }
            return results
        }
    }

    func evaluateApp(_ app: URL) async -> SecurityFinding? {
        if let id = Bundle(url: app)?.bundleIdentifier, trustedBundleIDs.contains(id) { return nil }
        let status = SignatureChecker.status(of: app)
        let title = app.deletingPathExtension().lastPathComponent
        var reasons: [String] = []
        var severity = SecurityFinding.Severity.review

        switch status {
        case .apple, .appStore:
            return nil
        case .invalid:
            severity = .suspicious
            reasons.append("The app's code signature is broken, so it was changed after it was signed.")
        case .unsigned:
            reasons.append("The app is not signed.")
        case .adHoc, .otherCertificate:
            reasons.append("The app is not signed by an identified developer.")
        case .developerID:
            if case .rejected(let source) = await gatekeeperAssessment(app) {
                reasons.append("Gatekeeper does not approve this app" + (source.map { " (\($0))" } ?? "") + ". It may not be notarized.")
            }
        }
        guard !reasons.isEmpty else { return nil }
        return SecurityFinding(kind: .application, path: app, title: title, reasons: reasons, severity: severity, signature: status)
    }

    enum GatekeeperResult: Equatable {
        case accepted(String?)
        case rejected(String?)
        case unknown
    }

    /// `spctl --assess --type execute -vv` (read-only).
    func gatekeeperAssessment(_ app: URL) async -> GatekeeperResult {
        guard let output = try? await commandRunner.run(
            "/usr/sbin/spctl", ["--assess", "--type", "execute", "-vv", app.path(percentEncoded: false)]
        ) else { return .unknown }
        let text = output.stderrText + output.stdoutText
        let source = text.split(separator: "\n")
            .first { $0.hasPrefix("source=") }
            .map { String($0.dropFirst("source=".count)) }
        if output.status == 0 { return .accepted(source) }
        if text.contains("rejected") { return .rejected(source) }
        return .unknown
    }
}
