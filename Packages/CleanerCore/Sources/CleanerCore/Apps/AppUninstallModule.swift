import CoreServices
import Foundation

/// Folders in ~/Library where apps keep their files.
enum LibraryLocations {
    struct Location: Sendable {
        let folder: String
        let label: String
        /// May hold your own documents or settings worth keeping.
        let risk: Risk
    }

    static let all: [Location] = [
        Location(folder: "Application Support", label: "Application Support", risk: .review),
        Location(folder: "Containers", label: "App container", risk: .review),
        Location(folder: "Group Containers", label: "Shared container", risk: .review),
        Location(folder: "Caches", label: "Caches", risk: .safe),
        Location(folder: "HTTPStorages", label: "Web data", risk: .safe),
        Location(folder: "WebKit", label: "Web data", risk: .safe),
        Location(folder: "Preferences", label: "Preferences", risk: .safe),
        Location(folder: "Saved Application State", label: "Saved window state", risk: .safe),
        Location(folder: "Logs", label: "Logs", risk: .safe),
        Location(folder: "Cookies", label: "Cookies", risk: .safe),
        Location(folder: "Application Scripts", label: "Scripts", risk: .safe),
        Location(folder: "LaunchAgents", label: "Startup items", risk: .safe),
    ]

    static func roots(_ context: ModuleContext) -> [URL] {
        all.map { context.library.appending(path: $0.folder, directoryHint: .isDirectory) }
    }
}

/// Removes an app (to the Trash, never permanently) together with the files
/// it left in ~/Library.
public struct AppUninstallModule: CleanupModule {
    public let category = CleanupCategory.applications
    public let appGuard: AppBundleGuard
    private let context: ModuleContext
    private let support: PathModuleSupport
    private let runningApps: @Sendable () -> [String]

    public init(
        context: ModuleContext,
        applicationFolders: [URL] = AppInventory.liveFolders(),
        runningApps: @escaping @Sendable () -> [String] = { AppInventory.runningExecutablePaths() }
    ) {
        self.context = context
        self.appGuard = AppBundleGuard(applicationFolders: applicationFolders)
        self.runningApps = runningApps
        support = PathModuleSupport(category: .applications, context: context, roots: LibraryLocations.roots(context))
    }

    /// Apps are listed by `AppInventory`; this module has nothing to scan on its own.
    public func scan() async -> [Finding] { [] }

    /// The app bundle plus every leftover found for it. Read-only.
    /// - Parameter otherApps: Other installed apps, so shared folders (same
    ///   team or same name) are not offered.
    public func plan(for app: InstalledApp, otherApps: [InstalledApp]) -> [Finding] {
        var findings: [Finding] = []
        if let validated = try? appGuard.validate(app.url, running: runningApps()) {
            let size = SizeCalculator.measure(validated.url)
            findings.append(Finding(
                category: category, target: .path(validated.url), group: "Application",
                reclaimableBytes: size?.reclaimableBytes ?? 0, risk: .review,
                scannedIdentity: validated, lastModified: size?.newestModification
            ))
        }
        let builder = FindingBuilder(category: category, risk: .safe, safetyGuard: support.safetyGuard,
                                     context: context, openFiles: context.openFiles())
        for candidate in Self.leftoverCandidates(for: app, otherApps: otherApps, context: context) {
            let riskBuilder = FindingBuilder(category: category, risk: candidate.risk, safetyGuard: builder.safetyGuard,
                                             context: context, openFiles: builder.openFiles)
            if let finding = riskBuilder.make(candidate.url, group: candidate.label) {
                findings.append(finding)
            }
        }
        return findings
    }

    struct Candidate {
        let url: URL
        let label: String
        let risk: Risk
    }

    static func leftoverCandidates(for app: InstalledApp, otherApps: [InstalledApp], context: ModuleContext) -> [Candidate] {
        let library = context.library
        let others = otherApps.filter { $0.url != app.url }
        let otherIDs = Set(others.compactMap(\.bundleID))
        let otherNames = Set(others.map(\.name))
        var result: [Candidate] = []

        func add(_ relative: String, label: String, risk: Risk) {
            let url = library.appending(path: relative)
            var st = stat()
            if lstat(url.path(percentEncoded: false), &st) == 0, !result.contains(where: { $0.url == url }) {
                result.append(Candidate(url: url, label: label, risk: risk))
            }
        }

        if let id = app.bundleID, !id.hasPrefix("com.apple."), !otherIDs.contains(id) {
            for location in LibraryLocations.all where !["Group Containers", "LaunchAgents", "Preferences"].contains(location.folder) {
                add("\(location.folder)/\(id)", label: location.label, risk: location.risk)
            }
            add("Preferences/\(id).plist", label: "Preferences", risk: .safe)
            add("Saved Application State/\(id).savedState", label: "Saved window state", risk: .safe)
            add("HTTPStorages/\(id).binarycookies", label: "Web data", risk: .safe)
            add("Cookies/\(id).binarycookies", label: "Cookies", risk: .safe)

            // Preferences/ByHost/<id>.<hardware UUID>.plist
            let byHost = library.appending(path: "Preferences/ByHost")
            for file in (try? FileManager.default.contentsOfDirectory(atPath: byHost.path(percentEncoded: false))) ?? []
            where file.hasPrefix(id + ".") && file.hasSuffix(".plist") {
                add("Preferences/ByHost/\(file)", label: "Preferences", risk: .safe)
            }
            // LaunchAgents named after the app (e.g. com.example.app.helper.plist).
            let agents = library.appending(path: "LaunchAgents")
            for file in (try? FileManager.default.contentsOfDirectory(atPath: agents.path(percentEncoded: false))) ?? []
            where file.hasPrefix(id) && file.hasSuffix(".plist") && !otherIDs.contains(where: { file.hasPrefix($0) }) {
                add("LaunchAgents/\(file)", label: "Startup items", risk: .safe)
            }
            // Group containers are shared by a developer's apps: only when no
            // other installed app comes from the same team.
            if let team = app.teamID, !others.contains(where: { $0.teamID == team }) {
                let groups = library.appending(path: "Group Containers")
                for folder in (try? FileManager.default.contentsOfDirectory(atPath: groups.path(percentEncoded: false))) ?? []
                where folder.hasPrefix(team + ".") {
                    add("Group Containers/\(folder)", label: "Shared container", risk: .review)
                }
            }
        }

        // Folders named after the app are a weaker match: Review, and only if
        // no other app has the same name.
        if !otherNames.contains(app.name), app.name.count > 2 {
            add("Application Support/\(app.name)", label: "Application Support", risk: .review)
            add("Caches/\(app.name)", label: "Caches", risk: .review)
            add("Logs/\(app.name)", label: "Logs", risk: .review)
        }
        return result
    }

    public func clean(_ findings: [Finding], mode: RemovalMode) async -> CleanResult {
        var result = CleanResult(mode: mode)
        var leftovers: [Finding] = []
        let running = runningApps()

        for finding in findings {
            guard finding.category == category, let url = finding.url else {
                result.failed.append(.init(findingID: finding.id, target: finding.target, reason: "Belongs to another category"))
                continue
            }
            guard url.pathExtension == "app", finding.group == "Application" else {
                leftovers.append(finding)
                continue
            }
            do throws(AppBundleGuard.Rejection) {
                let validated: SafetyGuard.ValidatedPath
                if let scanned = finding.scannedIdentity {
                    validated = try appGuard.revalidate(scanned, running: running)
                } else {
                    validated = try appGuard.validate(url, running: running)
                }
                switch mode {
                case .dryRun:
                    result.removed.append(.init(findingID: finding.id, target: finding.target, bytes: finding.reclaimableBytes, trashedURL: nil))
                case .deletePermanently:
                    result.failed.append(.init(findingID: finding.id, target: finding.target, reason: "Apps always go to the Trash"))
                case .moveToTrash:
                    do {
                        let trashed = try context.operations.moveToTrash(validated.url)
                        result.removed.append(.init(findingID: finding.id, target: finding.target, bytes: finding.reclaimableBytes, trashedURL: trashed))
                    } catch {
                        result.failed.append(.init(findingID: finding.id, target: finding.target, reason: error.localizedDescription))
                    }
                }
            } catch {
                result.failed.append(.init(findingID: finding.id, target: finding.target, reason: error.description))
            }
        }

        let removed = support.clean(leftovers, mode: mode)
        result.removed += removed.removed
        result.failed += removed.failed
        return result
    }
}

/// Files in ~/Library named after apps that are no longer installed.
public struct AppLeftoversModule: CleanupModule {
    public let category = CleanupCategory.appLeftovers
    private let support: PathModuleSupport
    private let isInstalled: @Sendable (String) -> Bool

    /// Caches are already covered by the System cache category.
    static let searched: [LibraryLocations.Location] = LibraryLocations.all.filter {
        ["Application Support", "Preferences", "Saved Application State", "HTTPStorages", "WebKit", "Logs", "Application Scripts"].contains($0.folder)
    }

    public init(context: ModuleContext, isInstalled: @escaping @Sendable (String) -> Bool = AppLeftoversModule.launchServicesKnows) {
        self.isInstalled = isInstalled
        support = PathModuleSupport(category: .appLeftovers, context: context, roots: LibraryLocations.roots(context))
    }

    public func scan() async -> [Finding] {
        let library = support.context.library
        let isInstalled = self.isInstalled
        return await support.scan(Self.searched.map { location in
            ScanSource(root: library.appending(path: location.folder), risk: .review, accessGroup: location.label) { root in
                try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                    .compactMap { url -> ScanSource.Candidate? in
                        guard let id = Self.bundleID(fromName: url.lastPathComponent),
                              !Self.belongsToInstalledApp(id, isInstalled: isInstalled)
                        else { return nil }
                        return (url: url, group: id)
                    }
            }
        })
    }

    public func clean(_ findings: [Finding], mode: RemovalMode) async -> CleanResult {
        support.clean(findings, mode: mode)
    }

    static let neverOffered = ["com.apple.", "io.github.maccleaner.", "group.", "systemgroup."]

    /// `com.example.App.plist` → `com.example.App`; nil for names that
    /// don't look like an app's bundle identifier.
    static func bundleID(fromName name: String) -> String? {
        var id = name
        for suffix in [".plist", ".savedState", ".binarycookies"] where id.hasSuffix(suffix) {
            id = String(id.dropLast(suffix.count))
        }
        guard AppNameResolver.looksLikeBundleID(id),
              id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-" || $0 == "_" }),
              !neverOffered.contains(where: id.hasPrefix)
        else { return nil }
        return id
    }

    /// True if this ID, or a parent ID (helpers like `com.example.App.helper`), is installed.
    static func belongsToInstalledApp(_ id: String, isInstalled: (String) -> Bool) -> Bool {
        var parts = id.split(separator: ".")
        while parts.count >= 2 {
            if isInstalled(parts.joined(separator: ".")) { return true }
            parts.removeLast()
        }
        return false
    }

    public static let launchServicesKnows: @Sendable (String) -> Bool = { id in
        guard let urls = LSCopyApplicationURLsForBundleIdentifier(id as CFString, nil)?.takeRetainedValue() as? [URL] else { return false }
        return !urls.isEmpty
    }
}
