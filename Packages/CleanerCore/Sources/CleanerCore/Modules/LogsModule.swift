import Foundation

/// `~/Library/Logs` (one finding per top-level entry) and individual crash
/// reports from `~/Library/Logs/DiagnosticReports`.
public struct LogsModule: CleanupModule {
    public let category = CleanupCategory.applicationLogs
    static let crashReportsFolder = "DiagnosticReports"
    public static let crashReportsGroup = "Crash reports"

    private let support: PathModuleSupport

    public init(context: ModuleContext) {
        support = PathModuleSupport(category: category, context: context, roots: [context.logs])
    }

    public func scan() async -> [Finding] {
        let logs = support.context.logs
        let reports = logs.appending(path: Self.crashReportsFolder, directoryHint: .isDirectory)
        return await support.scan([
            .topLevel(
                logs,
                risk: .safe,
                accessGroup: "Logs",
                include: { $0.lastPathComponent != Self.crashReportsFolder },
                group: { AppNameResolver.displayName(forFolderName: $0.deletingPathExtension().lastPathComponent) }
            ),
            .topLevel(reports, risk: .safe, accessGroup: Self.crashReportsGroup, group: { _ in Self.crashReportsGroup }),
        ])
    }

    public func clean(_ findings: [Finding], mode: RemovalMode) async -> CleanResult {
        support.clean(findings, mode: mode)
    }
}
