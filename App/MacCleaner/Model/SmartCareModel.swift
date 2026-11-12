import AppKit
import CleanerCore
import Observation

@MainActor
@Observable
final class SmartCareModel {
    enum Phase {
        case idle
        case scanning(ScanProgress)
        case results(SmartCareReport)
    }

    private(set) var phase: Phase = .idle
    var includeJunk = true
    var includeMalware = true
    var includePerformance = true
    var selectedRecommendations: Set<String> = []
    private(set) var lastScan: ScanRecord?
    private(set) var lastFinished: ScanComponent?

    let settings: AppSettings
    let cleanup: CleanupModel
    private var task: Task<Void, Never>?

    init(settings: AppSettings, cleanup: CleanupModel) {
        self.settings = settings
        self.cleanup = cleanup
        lastScan = try? settings.database?.lastScan()
    }

    var scope: ScanScope {
        var scope: ScanScope = []
        if includeJunk { scope.insert(.junk) }
        if includeMalware { scope.insert(.malware) }
        if includePerformance { scope.insert(.performance) }
        return scope
    }

    var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    func start() {
        guard !isScanning, !scope.isEmpty else { return }
        let scope = self.scope
        let orchestrator = ScanOrchestrator.live(context: settings.makeContext())
        phase = .scanning(ScanProgress(completed: 0, total: 1, justFinished: nil))
        lastFinished = nil

        task = Task {
            let report = await orchestrator.run(scope: scope) { progress in
                Task { @MainActor in self.update(progress) }
            }
            guard !Task.isCancelled else { return }
            if scope.contains(.junk) {
                cleanup.apply(report.junk, date: report.finishedAt)
            }
            selectedRecommendations = Set(report.recommendations.filter(\.isSelectedByDefault).map(\.id))
            lastScan = try? settings.database?.saveScan(report.record)
            phase = .results(report)
        }
    }

    private func update(_ progress: ScanProgress) {
        guard case .scanning(let current) = phase, progress.completed >= current.completed else { return }
        phase = .scanning(progress)
        if let finished = progress.justFinished { lastFinished = finished }
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
    }

    func reset() {
        phase = .idle
    }

    // MARK: Recommendations

    /// Findings of a recommendation that are still present (not yet cleaned).
    func remainingFindings(_ recommendation: Recommendation) -> [Finding] {
        recommendation.findingIDs.compactMap(cleanup.finding).filter(cleanup.isSelectable)
    }

    func remainingBytes(_ recommendation: Recommendation) -> Int64 {
        remainingFindings(recommendation).reduce(0) { $0 + $1.reclaimableBytes }
    }

    var selectedFindings: [Finding] {
        guard case .results(let report) = phase else { return [] }
        return report.recommendations
            .filter { selectedRecommendations.contains($0.id) }
            .flatMap(remainingFindings)
    }

    func toggle(_ recommendation: Recommendation) {
        if selectedRecommendations.contains(recommendation.id) {
            selectedRecommendations.remove(recommendation.id)
        } else {
            selectedRecommendations.insert(recommendation.id)
        }
    }

    func requestClean() {
        cleanup.requestClean(selectedFindings, permanent: false)
    }

    func perform(_ action: Recommendation.Action) {
        switch action {
        case .clean: break
        case .openLoginItemsSettings: NSWorkspace.shared.open(FullDiskAccess.loginItemsSettingsURL)
        case .openStorageSettings: NSWorkspace.shared.open(FullDiskAccess.storageSettingsURL)
        case .openActivityMonitor:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
        case .revealInFinder(let url): NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
