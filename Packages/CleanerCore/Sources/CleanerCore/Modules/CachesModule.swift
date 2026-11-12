import Foundation

/// `~/Library/Caches`, one finding per top-level folder, grouped by app.
/// Apps rebuild their caches on next launch.
public struct CachesModule: CleanupModule {
    public let category = CleanupCategory.systemCache

    /// Caches that hold state other than disposable data (iCloud sync,
    /// in-flight background downloads, account/keychain helpers, Mac Cleaner
    /// itself). Never offered.
    public static let protectedNames: Set<String> = [
        "CloudKit",
        "com.apple.bird",
        "com.apple.cloudd",
        "com.apple.CloudDocs",
        "com.apple.nsurlsessiond",
        "com.apple.akd",
        "com.apple.containermanagerd",
        "com.apple.iCloudHelper",
        "com.apple.ap.adprivacyd",
        "com.apple.homed",
        "com.apple.passd",
        "familycircled",
        "io.github.maccleaner.app",
    ]

    private let support: PathModuleSupport

    public init(context: ModuleContext) {
        support = PathModuleSupport(category: category, context: context, roots: [context.caches])
    }

    public func scan() async -> [Finding] {
        await support.scan([
            .topLevel(
                support.context.caches,
                risk: .safe,
                accessGroup: "Caches",
                include: { !Self.protectedNames.contains($0.lastPathComponent) },
                group: { AppNameResolver.displayName(forFolderName: $0.lastPathComponent) }
            ),
        ])
    }

    public func clean(_ findings: [Finding], mode: RemovalMode) async -> CleanResult {
        support.clean(findings, mode: mode)
    }
}
