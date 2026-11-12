import Foundation
import Testing
@testable import CleanerCore

/// A module that returns canned findings and records whether clean ran.
private struct StubModule: CleanupModule {
    let category: CleanupCategory
    let findings: [Finding]
    func scan() async -> [Finding] { findings }
    func clean(_ findings: [Finding], mode: RemovalMode) async -> CleanResult {
        Issue.record("Scanning must never call clean()")
        return CleanResult(mode: mode)
    }
}

private func finding(_ category: CleanupCategory, _ bytes: Int64, risk: Risk = .safe, skip: SkipReason? = nil,
                     target: FindingTarget? = nil) -> Finding {
    Finding(category: category, target: target ?? .path(URL(fileURLWithPath: "/x/\(UUID().uuidString)")),
            group: "G", reclaimableBytes: bytes, risk: risk, skipReason: skip)
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ScanProgress] = []
    func add(_ p: ScanProgress) { lock.withLock { items.append(p) } }
    var all: [ScanProgress] { lock.withLock { items } }
}

@Suite("Smart Care")
struct SmartCareTests {

    private let security = SecurityReport(
        findings: [SecurityFinding(kind: .launchItem, path: URL(fileURLWithPath: "/Users/x/Library/LaunchAgents/bad.plist"),
                                   title: "bad", reasons: ["Runs a program from a temporary or shared folder."],
                                   severity: .suspicious, signature: nil)],
        launchItemsChecked: 4, appsChecked: 20
    )

    private func snapshot(pressure: MemoryPressure = .normal, cpu: [ProcessCPU] = [], startup: Int = 0,
                          free: Int64 = 200_000_000_000, total: Int64 = 500_000_000_000) -> PerformanceSnapshot {
        let items = (0..<startup).map {
            LaunchItem(plist: URL(fileURLWithPath: "/L/\($0).plist"), scope: .userAgent, label: "com.example.\($0)",
                       program: "/bin/ls", arguments: [], runAtLoad: true, keepAlive: false, isBundleProgram: false, isReadable: true)
        }
        return PerformanceSnapshot(memoryPressure: pressure, memoryUsedBytes: 8 << 30, memoryTotalBytes: 16 << 30,
                                   topProcesses: cpu, startupItems: items, disk: DiskSpace(availableBytes: free, totalBytes: total))
    }

    private func orchestrator(_ modules: [any CleanupModule], perf: PerformanceSnapshot? = nil) -> ScanOrchestrator {
        let security = self.security
        let snap = perf ?? snapshot()
        return ScanOrchestrator(
            modules: modules,
            securityScan: { security },
            performanceScan: { PerformanceReport(snapshot: snap, issues: PerformanceRules.issues(for: snap)) }
        )
    }

    // MARK: Orchestrator

    @Test func runsAllComponentsAndReportsProgress() async {
        let modules: [any CleanupModule] = [
            StubModule(category: .systemCache, findings: [finding(.systemCache, 1000), finding(.systemCache, 500, skip: .inUse)]),
            StubModule(category: .applicationLogs, findings: [finding(.applicationLogs, 200)]),
            StubModule(category: .trash, findings: [finding(.trash, 300, risk: .review)]),
        ]
        let log = ProgressLog()
        let report = await orchestrator(modules).run(scope: .all) { log.add($0) }

        #expect(report.junkBytes == 1500, "Skipped items are not counted")
        #expect(report.junkCategoryCount == 3)
        #expect(report.threatCount == 1)
        #expect(report.security != nil && report.performance != nil)
        let progress = log.all
        #expect(progress.first?.completed == 0)
        #expect(progress.last?.completed == 5 && progress.last?.total == 5)
        #expect(progress.map(\.completed) == Array(0...5))
        #expect(report.record.junkItemCount == 3)
    }

    @Test func scopeLimitsComponents() async {
        let modules: [any CleanupModule] = [StubModule(category: .systemCache, findings: [finding(.systemCache, 10)])]
        let perfOnly = await orchestrator(modules).run(scope: .performance)
        #expect(perfOnly.junk.isEmpty)
        #expect(perfOnly.security == nil)
        #expect(perfOnly.performance != nil)

        let junkOnly = await orchestrator(modules).run(scope: .junk)
        #expect(junkOnly.allFindings.count == 1)
        #expect(junkOnly.security == nil && junkOnly.performance == nil)
    }

    @Test func reportsInaccessibleCategories() async {
        let modules: [any CleanupModule] = [
            StubModule(category: .mailAttachments, findings: [finding(.mailAttachments, 0, risk: .review, skip: .needsFullDiskAccess)]),
        ]
        let report = await orchestrator(modules).run(scope: .junk)
        #expect(report.inaccessibleCategories == [.mailAttachments])
        #expect(report.junkBytes == 0)
    }

    // MARK: Rule engine

    @Test func groupsFindingsIntoSafeAndReviewRecommendations() {
        let sims = finding(.xcodeJunk, 900, target: .command(.deleteUnavailableSimulators))
        let junk: [CleanupCategory: [Finding]] = [
            .systemCache: [finding(.systemCache, 100), finding(.systemCache, 50, skip: .recentlyModified)],
            .applicationLogs: [finding(.applicationLogs, 10)],
            .xcodeJunk: [finding(.xcodeJunk, 1000), sims, finding(.xcodeJunk, 400, risk: .review)],
            .trash: [finding(.trash, 70, risk: .review)],
            .mailAttachments: [finding(.mailAttachments, 0, risk: .review)],
        ]
        let recs = RuleEngine.recommendations(junk: junk, security: nil, performance: nil)
        let byID = Dictionary(uniqueKeysWithValues: recs.map { ($0.id, $0) })

        #expect(byID["cache-logs"]?.bytes == 110, "Skipped items excluded")
        #expect(byID["cache-logs"]?.findingIDs.count == 2)
        #expect(byID["cache-logs"]?.isSelectedByDefault == true)
        #expect(byID["xcode"]?.bytes == 1900)
        #expect(byID["xcode"]?.includesPermanentDeletion == true)
        #expect(byID["archives"]?.risk == .review)
        #expect(byID["archives"]?.isSelectedByDefault == false)
        #expect(byID["trash"]?.risk == .review)
        #expect(byID["trash"]?.includesPermanentDeletion == true)
        #expect(byID["trash"]?.isSelectedByDefault == false)
        #expect(byID["mail"] == nil, "Zero-byte groups are not recommended")
        #expect(byID["temp-downloads"] == nil)
    }

    @Test func securityAndPerformanceBecomeReviewActions() {
        let perf = snapshot(pressure: .warning, cpu: [ProcessCPU(pid: 42, name: "Renderer", percent: 95)], startup: 7, free: 5_000_000_000)
        let report = PerformanceReport(snapshot: perf, issues: PerformanceRules.issues(for: perf))
        let recs = RuleEngine.recommendations(junk: [:], security: security, performance: report)

        #expect(recs.allSatisfy { $0.risk == .review && !$0.isSelectedByDefault && $0.findingIDs.isEmpty })
        #expect(recs.contains { $0.action == .revealInFinder(URL(fileURLWithPath: "/Users/x/Library/LaunchAgents/bad.plist")) })
        #expect(recs.contains { $0.title == "Review login items that slow startup" && $0.action == .openLoginItemsSettings })
        #expect(recs.contains { $0.action == .openStorageSettings })
        #expect(recs.filter { $0.action == .openActivityMonitor }.count == 2)
    }

    // MARK: Performance rules

    @Test func healthySnapshotHasNoIssues() {
        #expect(PerformanceRules.issues(for: snapshot()).isEmpty)
    }

    @Test func performanceThresholds() {
        let cpu = [
            ProcessCPU(pid: 1, name: "A", percent: 180), ProcessCPU(pid: 2, name: "B", percent: 75),
            ProcessCPU(pid: 3, name: "C", percent: 61), ProcessCPU(pid: 4, name: "D", percent: 60),
            ProcessCPU(pid: 5, name: "E", percent: 20),
        ]
        let kinds = PerformanceRules.issues(for: snapshot(pressure: .critical, cpu: cpu, startup: 6, free: 40_000_000_000, total: 500_000_000_000)).map(\.kind)
        #expect(kinds.filter { $0 == .cpuHog }.count == 3, "At most three CPU hogs")
        #expect(kinds.contains(.memoryPressure))
        #expect(kinds.contains(.startupItems))
        #expect(kinds.contains(.lowDiskSpace), "8% free is low")

        #expect(PerformanceRules.issues(for: snapshot(startup: 5)).isEmpty)
        #expect(PerformanceRules.issues(for: snapshot(free: 14_000_000_000, total: 100_000_000_000)).map(\.kind) == [.lowDiskSpace])
    }

    @Test func appleStartupItemsDoNotCount() {
        var snap = snapshot()
        snap.startupItems = (0..<10).map {
            LaunchItem(plist: URL(fileURLWithPath: "/L/\($0).plist"), scope: .systemAgent, label: "com.apple.\($0)",
                       program: "/bin/ls", arguments: [], runAtLoad: true, keepAlive: true, isBundleProgram: false, isReadable: true)
        }
        #expect(PerformanceRules.issues(for: snap).isEmpty)
    }

    @Test func liveCheckerCollectsSaneValues() async {
        let snap = await PerformanceChecker(sampleInterval: .milliseconds(200)).collect()
        #expect(snap.memoryTotalBytes > 0)
        #expect(snap.memoryUsedBytes > 0 && snap.memoryUsedBytes <= snap.memoryTotalBytes)
        #expect((snap.disk?.totalBytes ?? 0) > 0)
        #expect(snap.topProcesses.allSatisfy { $0.percent >= 0 && !$0.name.isEmpty })
        #expect(!snap.topProcesses.contains { $0.pid == getpid() })
    }
}
