import Foundation

/// Lists the top-level items in the user's Trash (`~/.Trash`).
///
/// Emptying the Trash cannot be undone, so every finding is `.review`, and
/// `clean` refuses `.moveToTrash`: callers must pass `.deletePermanently`
/// (after the extra confirmation) or `.dryRun`.
///
/// v1 covers the home-volume Trash only. Trash folders on other volumes live
/// under `/Volumes`, which `SafetyGuard` blocks.
public struct TrashModule: CleanupModule {
    public let category = CleanupCategory.trash
    public static let requiresPermanentDeletion = true
    public static let groupName = "Trash"

    private let context: ModuleContext
    public let safetyGuard: SafetyGuard

    public init(context: ModuleContext) {
        self.context = context
        self.safetyGuard = SafetyGuard(allowedRoots: [context.trash], home: context.home)
    }

    public func scan() async -> [Finding] {
        let builder = FindingBuilder(
            category: category,
            risk: .review,
            safetyGuard: safetyGuard,
            context: context,
            openFiles: context.openFiles()
        )

        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: context.trash,
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            // macOS hides ~/.Trash from apps without Full Disk Access.
            return FindingBuilder.isPermissionError(error)
                ? [builder.needsAccess(context.trash, group: Self.groupName)]
                : []
        }

        let candidates = entries
            .filter { $0.lastPathComponent != ".DS_Store" }
            .map { (url: $0, group: Self.groupName) }
        return await builder.makeAll(candidates)
    }

    public func clean(_ findings: [Finding], mode: RemovalMode) async -> CleanResult {
        var result = CleanResult(mode: mode)
        var accepted: [Finding] = []
        for finding in findings {
            if finding.category != category {
                result.failed.append(.init(findingID: finding.id, target: finding.target, reason: "Not a Trash item"))
            } else if mode == .moveToTrash {
                result.failed.append(.init(
                    findingID: finding.id,
                    target: finding.target,
                    reason: "Already in the Trash. Choose “Delete permanently” to remove it."
                ))
            } else {
                accepted.append(finding)
            }
        }
        let removed = Remover(safetyGuard: safetyGuard, context: context).remove(accepted, mode: mode)
        result.removed += removed.removed
        result.failed += removed.failed
        return result
    }
}
