import Foundation

/// Package-manager caches outside `~/Library/Caches` (npm, Gradle, Cargo,
/// Go, Dart, CocoaPods). All are re-downloaded on demand.
public struct DeveloperCachesModule: CleanupModule {
    public let category = CleanupCategory.developerCaches

    struct Spec: Sendable {
        let parent: String   // relative to home; this is the guard root
        let child: String    // the folder that is offered
        let group: String
        let risk: Risk
    }

    static let specs: [Spec] = [
        Spec(parent: ".npm", child: "_cacache", group: "npm", risk: .safe),
        Spec(parent: ".gradle", child: "caches", group: "Gradle", risk: .safe),
        Spec(parent: ".cargo/registry", child: "cache", group: "Cargo", risk: .safe),
        Spec(parent: "go/pkg/mod/cache", child: "download", group: "Go modules", risk: .safe),
        Spec(parent: ".pub-cache", child: "hosted", group: "Dart & Flutter", risk: .safe),
        Spec(parent: ".cocoapods", child: "repos", group: "CocoaPods", risk: .safe),
        // `mvn install` puts your own builds here too, so it's Review.
        Spec(parent: ".m2", child: "repository", group: "Maven", risk: .review),
    ]

    private let support: PathModuleSupport

    public init(context: ModuleContext) {
        support = PathModuleSupport(
            category: category, context: context,
            roots: Self.specs.map { context.home.appending(path: $0.parent, directoryHint: .isDirectory) }
        )
    }

    public func scan() async -> [Finding] {
        let home = support.context.home
        return await support.scan(Self.specs.map { spec in
            ScanSource(root: home.appending(path: spec.parent), risk: spec.risk, accessGroup: spec.group) { root in
                let url = root.appending(path: spec.child, directoryHint: .isDirectory)
                return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? [(url: url, group: spec.group)] : []
            }
        })
    }

    public func clean(_ findings: [Finding], mode: RemovalMode) async -> CleanResult {
        support.clean(findings, mode: mode)
    }
}

/// iPhone/iPad software updates downloaded by Finder (`.ipsw`).
public struct IOSUpdatesModule: CleanupModule {
    public let category = CleanupCategory.iosUpdates
    private let support: PathModuleSupport
    private let roots: [URL]

    public init(context: ModuleContext) {
        roots = ["iPhone Software Updates", "iPad Software Updates", "iPod Software Updates"].map {
            context.library.appending(path: "iTunes/\($0)", directoryHint: .isDirectory)
        }
        support = PathModuleSupport(category: category, context: context, roots: roots)
    }

    public func scan() async -> [Finding] {
        await support.scan(roots.map {
            .topLevel($0, risk: .safe, accessGroup: "iOS updates",
                      include: { $0.pathExtension.lowercased() == "ipsw" }, group: { _ in "iOS updates" })
        })
    }

    public func clean(_ findings: [Finding], mode: RemovalMode) async -> CleanResult {
        support.clean(findings, mode: mode)
    }
}

/// Device backups made by Finder. Often large, and sometimes the only copy
/// of a device's data, so they are Review.
public struct IOSBackupsModule: CleanupModule {
    public let category = CleanupCategory.iosBackups
    private let support: PathModuleSupport
    private let root: URL

    public init(context: ModuleContext) {
        root = context.library.appending(path: "Application Support/MobileSync/Backup", directoryHint: .isDirectory)
        support = PathModuleSupport(category: category, context: context, roots: [root])
    }

    public func scan() async -> [Finding] {
        await support.scan([
            .topLevel(root, risk: .review, accessGroup: "Device backups", group: Self.deviceName),
        ])
    }

    public func clean(_ findings: [Finding], mode: RemovalMode) async -> CleanResult {
        support.clean(findings, mode: mode)
    }

    static func deviceName(_ backup: URL) -> String {
        guard let data = try? Data(contentsOf: backup.appending(path: "Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let name = info["Device Name"] as? String
        else { return "Device backup" }
        return name
    }
}

/// Disk images and installer packages in Downloads older than a week.
public struct InstallersModule: CleanupModule {
    public let category = CleanupCategory.installers
    public static let extensions: [String: String] = [
        "dmg": "Disk images", "iso": "Disk images",
        "pkg": "Installer packages", "mpkg": "Installer packages", "xip": "Installer packages",
    ]
    public static let minimumAge: TimeInterval = 7 * 86_400

    private let support: PathModuleSupport

    public init(context: ModuleContext) {
        support = PathModuleSupport(category: category, context: context, roots: [context.downloads])
    }

    public func scan() async -> [Finding] {
        let cutoff = support.context.now().addingTimeInterval(-Self.minimumAge)
        let source = ScanSource.topLevel(
            support.context.downloads, risk: .review, accessGroup: "Downloads",
            include: { url in
                guard Self.extensions[url.pathExtension.lowercased()] != nil else { return false }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                return (modified ?? .distantFuture) < cutoff
            },
            group: { Self.extensions[$0.pathExtension.lowercased()] ?? "Installers" }
        )
        return await support.scan([source])
    }

    public func clean(_ findings: [Finding], mode: RemovalMode) async -> CleanResult {
        support.clean(findings, mode: mode)
    }
}

/// Your own startup items (`~/Library/LaunchAgents`) whose program no longer
/// exists. They fail on every login.
public struct BrokenStartupItemsModule: CleanupModule {
    public let category = CleanupCategory.brokenStartupItems
    private let support: PathModuleSupport
    private let root: URL

    public init(context: ModuleContext) {
        root = context.library.appending(path: "LaunchAgents", directoryHint: .isDirectory)
        support = PathModuleSupport(category: category, context: context, roots: [root])
    }

    public func scan() async -> [Finding] {
        let source = ScanSource(root: root, risk: .review, accessGroup: "Startup items") { root in
            _ = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            return LaunchItemInventory.items(in: [(root, .userAgent)])
                .filter(Self.isBroken)
                .map { (url: $0.plist, group: "Startup items") }
        }
        return await support.scan([source])
    }

    public func clean(_ findings: [Finding], mode: RemovalMode) async -> CleanResult {
        support.clean(findings, mode: mode)
    }

    static func isBroken(_ item: LaunchItem) -> Bool {
        guard item.isReadable, !item.isBundleProgram, !item.isApple, let program = item.program else { return false }
        return !FileManager.default.fileExists(atPath: LaunchItemInventory.resolveProgram(program))
    }
}
