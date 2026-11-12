import Foundation

/// The standard set of cleanup modules.
public enum ModuleRegistry {
    public static func standard(context: ModuleContext) -> [any CleanupModule] {
        [
            CachesModule(context: context),
            LogsModule(context: context),
            TemporaryFilesModule(context: context),
            BrokenDownloadsModule(context: context),
            MailAttachmentsModule(context: context),
            TrashModule(context: context),
            XcodeJunkModule(context: context),
            DeveloperCachesModule(context: context),
            IOSUpdatesModule(context: context),
            IOSBackupsModule(context: context),
            InstallersModule(context: context),
            BrokenStartupItemsModule(context: context),
        ]
    }

    /// Junk modules plus the tools. Used for cleaning, so any finding can be
    /// routed to the module that made it.
    public static func all(context: ModuleContext) -> [any CleanupModule] {
        standard(context: context) + [
            LargeOldFilesModule(context: context),
            DuplicatesModule(context: context),
            AppUninstallModule(context: context),
            AppLeftoversModule(context: context),
        ]
    }
}

/// Routes selected findings to their modules and records every outcome in
/// the activity log (including dry runs and skipped items).
public struct CleanupService: Sendable {
    private let modules: [CleanupCategory: any CleanupModule]
    private let database: AppDatabase?
    private let now: @Sendable () -> Date

    public init(modules: [any CleanupModule], database: AppDatabase?, now: @escaping @Sendable () -> Date = { Date() }) {
        self.modules = Dictionary(modules.map { ($0.category, $0) }, uniquingKeysWith: { first, _ in first })
        self.database = database
        self.now = now
    }

    public func clean(_ findings: [Finding], mode: RemovalMode) async -> CleanResult {
        let byCategory = Dictionary(grouping: findings, by: \.category)
        var results: [CleanResult] = []
        for category in CleanupCategory.allCases {
            guard let items = byCategory[category], !items.isEmpty else { continue }
            guard let module = modules[category] else {
                results.append(CleanResult(mode: mode, failed: items.map {
                    .init(findingID: $0.id, target: $0.target, reason: "No module for \(category.displayName)")
                }))
                continue
            }
            results.append(await module.clean(items, mode: mode))
        }
        let merged = CleanResult.merged(results, mode: mode)
        log(merged, findings: findings)
        return merged
    }

    private func log(_ result: CleanResult, findings: [Finding]) {
        guard let database else { return }
        let lookup = Dictionary(findings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let date = now()
        let removedOutcome: ActionLogEntry.Outcome = switch result.mode {
        case .dryRun: .simulated
        case .moveToTrash: .movedToTrash
        case .deletePermanently: .deleted
        }

        var entries: [ActionLogEntry] = result.removed.compactMap { item in
            guard let finding = lookup[item.findingID] else { return nil }
            return ActionLogEntry(
                date: date, mode: result.mode, category: finding.category, target: finding.displayPath,
                bytes: item.bytes, outcome: removedOutcome,
                detail: result.mode == .dryRun ? "Dry run: nothing was changed" : nil,
                trashedPath: item.trashedURL?.path(percentEncoded: false)
            )
        }
        entries += result.failed.compactMap { item in
            guard let finding = lookup[item.findingID] else { return nil }
            return ActionLogEntry(
                date: date, mode: result.mode, category: finding.category, target: finding.displayPath,
                bytes: 0, outcome: .skipped, detail: item.reason
            )
        }
        try? database.appendActions(entries)
    }
}
