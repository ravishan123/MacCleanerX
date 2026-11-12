import Foundation

/// Top-level items in the user's own `$TMPDIR` (`/private/var/folders/…/T`).
/// Sockets and other special files are never offered, and anything open or
/// recently changed is left unchecked.
public struct TemporaryFilesModule: CleanupModule {
    public let category = CleanupCategory.temporaryFiles
    private let support: PathModuleSupport

    public init(context: ModuleContext) {
        support = PathModuleSupport(category: category, context: context, roots: [context.temporaryDirectory])
    }

    public func scan() async -> [Finding] {
        await support.scan([
            .topLevel(
                support.context.temporaryDirectory,
                risk: .safe,
                accessGroup: "Temporary files",
                include: { PathModuleSupport.isRegularOrDirectory($0) },
                group: { url in
                    let name = url.lastPathComponent
                    return AppNameResolver.looksLikeBundleID(name)
                        ? AppNameResolver.displayName(forFolderName: name)
                        : "Temporary files"
                }
            ),
        ])
    }

    public func clean(_ findings: [Finding], mode: RemovalMode) async -> CleanResult {
        support.clean(findings, mode: mode)
    }
}
