import AppKit
import CleanerCore
import Observation

enum TriState { case off, on, mixed }

/// Findings, selection and cleaning, shared by the Cleanup and Smart Care
/// screens.
@MainActor
@Observable
final class CleanupModel {
    enum Phase: Equatable { case idle, scanning, ready, cleaning }

    private(set) var phase: Phase = .idle
    private(set) var findings: [CleanupCategory: [Finding]] = [:]
    private(set) var loadedCategories: Set<CleanupCategory> = []
    private(set) var lastScanDate: Date?
    var selection: Set<UUID> = []
    var focusedCategory: CleanupCategory? = .systemCache
    /// Always off when the app starts.
    var permanentDelete = false
    /// Set to start the confirmation flow.
    var pendingPlan: CleanPlan?
    var outcome: CleanOutcome?
    /// Findings removed so far (any screen), so tool screens can hide them.
    private(set) var removedIDs: Set<UUID> = []

    let settings: AppSettings
    private var scanTask: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: Scanning (read-only)

    func scan() {
        guard phase != .scanning, phase != .cleaning else { return }
        scanTask?.cancel()
        phase = .scanning
        findings = [:]
        loadedCategories = []
        selection = []
        let modules = ModuleRegistry.standard(context: settings.makeContext())

        scanTask = Task {
            await withTaskGroup(of: (CleanupCategory, [Finding]).self) { group in
                for module in modules {
                    group.addTask { (module.category, await module.scan()) }
                }
                for await (category, items) in group {
                    guard !Task.isCancelled else { continue }
                    findings[category] = items
                    loadedCategories.insert(category)
                    selection.formUnion(items.filter(\.isSelectedByDefault).map(\.id))
                }
            }
            if !Task.isCancelled {
                lastScanDate = Date()
                phase = .ready
            }
        }
    }

    /// Adopt findings from a Smart Care scan.
    func apply(_ newFindings: [CleanupCategory: [Finding]], date: Date) {
        scanTask?.cancel()
        findings = newFindings
        loadedCategories = Set(newFindings.keys)
        selection = Set(allFindings.filter(\.isSelectedByDefault).map(\.id))
        lastScanDate = date
        phase = .ready
    }

    // MARK: Queries

    var allFindings: [Finding] { CleanupCategory.junkCases.flatMap { findings[$0] ?? [] } }

    func items(in category: CleanupCategory) -> [Finding] { findings[category] ?? [] }

    func groups(in category: CleanupCategory) -> [(name: String, items: [Finding])] {
        Dictionary(grouping: items(in: category), by: \.group)
            .map { (name: $0.key, items: $0.value.sorted { $0.reclaimableBytes > $1.reclaimableBytes }) }
            .sorted { bytes($0.items) > bytes($1.items) }
    }

    func bytes(_ items: [Finding]) -> Int64 {
        items.filter { $0.skipReason == nil }.reduce(0) { $0 + $1.reclaimableBytes }
    }

    func finding(_ id: UUID) -> Finding? { allFindings.first { $0.id == id } }

    var selectedFindings: [Finding] { allFindings.filter { selection.contains($0.id) && isSelectable($0) } }
    var selectedBytes: Int64 { selectedFindings.reduce(0) { $0 + $1.reclaimableBytes } }

    func needsAccess(_ category: CleanupCategory) -> Bool {
        items(in: category).contains { $0.skipReason == .needsFullDiskAccess }
    }

    // MARK: Selection

    /// In-use, recently changed and inaccessible items can't be checked.
    func isSelectable(_ finding: Finding) -> Bool { finding.skipReason == nil }

    func selectionState(_ items: [Finding]) -> TriState {
        let selectable = items.filter(isSelectable)
        guard !selectable.isEmpty else { return .off }
        let chosen = selectable.filter { selection.contains($0.id) }.count
        return chosen == 0 ? .off : chosen == selectable.count ? .on : .mixed
    }

    func setSelected(_ items: [Finding], _ on: Bool) {
        let ids = items.filter(isSelectable).map(\.id)
        if on { selection.formUnion(ids) } else { selection.subtract(ids) }
    }

    func toggle(_ items: [Finding]) {
        setSelected(items, selectionState(items) != .on)
    }

    // MARK: Cleaning

    /// Starts the confirmation flow. `permanent` defaults to the Cleanup
    /// screen's toggle; other screens always pass false (Trash only).
    func requestClean(_ items: [Finding]? = nil, permanent: Bool? = nil) {
        let chosen = (items ?? selectedFindings).filter(isSelectable)
        guard !chosen.isEmpty else { return }
        pendingPlan = CleanPlan(findings: chosen, dryRun: settings.dryRun, permanentToggle: permanent ?? permanentDelete)
    }

    /// Runs a plan the user has confirmed.
    func perform(_ plan: CleanPlan) async {
        guard phase != .cleaning else { return }
        phase = .cleaning
        let service = CleanupService(modules: ModuleRegistry.all(context: settings.makeContext()), database: settings.database)
        var results: [CleanResult] = []
        if !plan.regular.isEmpty { results.append(await service.clean(plan.regular, mode: plan.regularMode)) }
        if !plan.permanentOnly.isEmpty { results.append(await service.clean(plan.permanentOnly, mode: plan.permanentOnlyMode)) }
        let merged = CleanResult.merged(results, mode: plan.regularMode)

        if !plan.dryRun {
            let removed = Set(merged.removed.map(\.findingID))
            for category in findings.keys {
                findings[category]?.removeAll { removed.contains($0.id) }
            }
            selection.subtract(removed)
            removedIDs.formUnion(removed)
        }
        outcome = CleanOutcome(result: merged, dryRun: plan.dryRun, findings: Dictionary(plan.all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }))
        settings.reloadActivity()
        phase = .ready
    }

    // MARK: Item actions

    func exclude(_ finding: Finding) {
        guard let url = finding.url else { return }
        settings.addExclusion(url)
        for category in findings.keys {
            findings[category]?.removeAll { $0.id == finding.id }
        }
        selection.remove(finding.id)
    }

    func reveal(_ finding: Finding) {
        guard let url = finding.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
