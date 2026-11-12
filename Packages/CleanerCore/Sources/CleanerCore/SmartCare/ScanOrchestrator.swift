import Foundation

public struct ScanScope: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let junk = ScanScope(rawValue: 1 << 0)
    public static let malware = ScanScope(rawValue: 1 << 1)
    public static let performance = ScanScope(rawValue: 1 << 2)
    public static let all: ScanScope = [.junk, .malware, .performance]
}

public enum ScanComponent: Hashable, Sendable {
    case cleanup(CleanupCategory)
    case security
    case performance

    public var title: String {
        switch self {
        case .cleanup(let category): category.displayName
        case .security: "Startup items and apps"
        case .performance: "Memory, CPU and disk"
        }
    }
}

public struct ScanProgress: Sendable, Hashable {
    public let completed: Int
    public let total: Int
    public let justFinished: ScanComponent?

    public init(completed: Int, total: Int, justFinished: ScanComponent?) {
        self.completed = completed
        self.total = total
        self.justFinished = justFinished
    }

    public var fraction: Double { total == 0 ? 1 : Double(completed) / Double(total) }
}

public struct SmartCareReport: Sendable {
    public let startedAt: Date
    public let finishedAt: Date
    public let scope: ScanScope
    public let junk: [CleanupCategory: [Finding]]
    public let security: SecurityReport?
    public let performance: PerformanceReport?
    public let recommendations: [Recommendation]

    public var allFindings: [Finding] { CleanupCategory.junkCases.flatMap { junk[$0] ?? [] } }
    /// Reclaimable bytes of everything that can actually be cleaned.
    public var junkBytes: Int64 {
        allFindings.filter { $0.skipReason == nil }.reduce(0) { $0 + $1.reclaimableBytes }
    }
    public var junkCategoryCount: Int {
        junk.values.filter { $0.contains { $0.skipReason == nil && $0.reclaimableBytes > 0 } }.count
    }
    public var inaccessibleCategories: [CleanupCategory] {
        CleanupCategory.junkCases.filter { junk[$0]?.contains { $0.skipReason == .needsFullDiskAccess } == true }
    }
    public var threatCount: Int { security?.threatCount ?? 0 }
    public var performanceIssueCount: Int { performance?.issues.count ?? 0 }

    public var record: ScanRecord {
        ScanRecord(
            startedAt: startedAt, finishedAt: finishedAt, junkBytes: junkBytes,
            junkItemCount: allFindings.count { $0.skipReason == nil },
            threatCount: threatCount, performanceIssueCount: performanceIssueCount
        )
    }
}

/// Runs the selected scan components concurrently. Read-only: scanning never
/// modifies anything.
public struct ScanOrchestrator: Sendable {
    public var modules: [any CleanupModule]
    public var securityScan: @Sendable () async -> SecurityReport
    public var performanceScan: @Sendable () async -> PerformanceReport
    public var now: @Sendable () -> Date

    public init(
        modules: [any CleanupModule],
        securityScan: @escaping @Sendable () async -> SecurityReport,
        performanceScan: @escaping @Sendable () async -> PerformanceReport,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.modules = modules
        self.securityScan = securityScan
        self.performanceScan = performanceScan
        self.now = now
    }

    public static func live(context: ModuleContext) -> ScanOrchestrator {
        let security = SecurityScanner.live(home: context.home)
        let performance = PerformanceChecker(home: context.home)
        return ScanOrchestrator(
            modules: ModuleRegistry.standard(context: context),
            securityScan: { await security.scan() },
            performanceScan: { await performance.run() }
        )
    }

    private enum Partial: Sendable {
        case junk(CleanupCategory, [Finding])
        case security(SecurityReport)
        case performance(PerformanceReport)
    }

    public func run(scope: ScanScope, progress: @escaping @Sendable (ScanProgress) -> Void = { _ in }) async -> SmartCareReport {
        let started = now()
        let modules = scope.contains(.junk) ? self.modules : []
        let total = modules.count + (scope.contains(.malware) ? 1 : 0) + (scope.contains(.performance) ? 1 : 0)
        progress(ScanProgress(completed: 0, total: total, justFinished: nil))

        var junk: [CleanupCategory: [Finding]] = [:]
        var security: SecurityReport?
        var performance: PerformanceReport?

        enum Job: Sendable {
            case junk(any CleanupModule), security, performance
        }
        var jobs: [Job] = []
        // Start the quick checks first so progress moves right away.
        if scope.contains(.malware) { jobs.append(.security) }
        if scope.contains(.performance) { jobs.append(.performance) }
        jobs += modules.map(Job.junk)

        let securityScan = self.securityScan
        let performanceScan = self.performanceScan
        var completed = 0
        await ScanLimits.run(jobs, work: { job -> Partial in
            switch job {
            case .junk(let module): .junk(module.category, await module.scan())
            case .security: .security(await securityScan())
            case .performance: .performance(await performanceScan())
            }
        }, onResult: { partial in
            completed += 1
            let component: ScanComponent
            switch partial {
            case .junk(let category, let findings):
                junk[category, default: []] += findings
                component = .cleanup(category)
            case .security(let report):
                security = report
                component = .security
            case .performance(let report):
                performance = report
                component = .performance
            }
            progress(ScanProgress(completed: completed, total: total, justFinished: component))
        })

        let recommendations = RuleEngine.recommendations(junk: junk, security: security, performance: performance)
        return SmartCareReport(
            startedAt: started, finishedAt: now(), scope: scope, junk: junk,
            security: security, performance: performance, recommendations: recommendations
        )
    }
}
