import AppKit
import CleanerCore
import Observation

/// Findings + selection for a tool screen (Large & old, Duplicates,
/// Leftovers). Cleaning always goes through `CleanupModel`'s confirmation.
@MainActor
@Observable
final class FindingsTool {
    enum Phase: Equatable { case idle, scanning, ready }

    private(set) var phase: Phase = .idle
    private(set) var findings: [Finding] = []
    var selection: Set<UUID> = []
    let cleanup: CleanupModel
    private var task: Task<Void, Never>?

    init(cleanup: CleanupModel) {
        self.cleanup = cleanup
    }

    func scan(_ work: @escaping @Sendable () async -> [Finding]) {
        task?.cancel()
        phase = .scanning
        findings = []
        selection = []
        task = Task {
            let result = await Task.detached(priority: .userInitiated) { await work() }.value
            guard !Task.isCancelled else { return }
            findings = result
            selection = Set(result.filter(\.isSelectedByDefault).map(\.id))
            phase = .ready
        }
    }

    func cancel() {
        task?.cancel()
        phase = findings.isEmpty ? .idle : .ready
    }

    var visible: [Finding] { findings.filter { !cleanup.removedIDs.contains($0.id) } }

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

    var selected: [Finding] { visible.filter { selection.contains($0.id) && isSelectable($0) } }
    var selectedBytes: Int64 { selected.reduce(0) { $0 + $1.reclaimableBytes } }

    func groups(by key: (Finding) -> String) -> [(name: String, items: [Finding])] {
        Dictionary(grouping: visible, by: key)
            .map { (name: $0.key, items: $0.value.sorted { $0.reclaimableBytes > $1.reclaimableBytes }) }
            .sorted { $0.items.reduce(0) { $0 + $1.reclaimableBytes } > $1.items.reduce(0) { $0 + $1.reclaimableBytes } }
    }

    /// Tools always move items to the Trash.
    func requestClean() {
        cleanup.requestClean(selected, permanent: false)
    }
}

// MARK: - Duplicates

extension FindingsTool {
    func copies(of finding: Finding) -> [Finding] {
        visible.filter { $0.duplicateSet == finding.duplicateSet }
    }

    /// One copy in every set must stay unselected.
    func canSelectCopy(_ finding: Finding) -> Bool {
        let set = copies(of: finding)
        let selectedAfter = set.filter { selection.contains($0.id) || $0.id == finding.id }.count
        return selectedAfter < set.count
    }

    /// Selects every copy except the oldest one in each set.
    func selectAllButOldest() {
        var ids = Set<UUID>()
        for (_, set) in Dictionary(grouping: visible.filter(isSelectable), by: { $0.duplicateSet ?? "" }) where set.count > 1 {
            let keep = set.min { ($0.lastModified ?? .distantFuture) < ($1.lastModified ?? .distantFuture) }
            ids.formUnion(set.filter { $0.id != keep?.id }.map(\.id))
        }
        selection = ids
    }
}

// MARK: - Storage

@MainActor
@Observable
final class StorageModel {
    enum Phase { case idle, scanning(files: Int), ready(StorageReport) }

    private(set) var phase: Phase = .idle
    var focused: StorageCategory?
    private var task: Task<Void, Never>?

    var isScanning: Bool {
        if case .scanning = phase { return true }
        return false
    }

    func scan() {
        task?.cancel()
        phase = .scanning(files: 0)
        let scanner = StorageScanner.live()
        task = Task {
            let report = await Task.detached(priority: .userInitiated) {
                await scanner.scan { files in
                    Task { @MainActor in self.progress(files) }
                }
            }.value
            guard !Task.isCancelled else { return }
            focused = focused ?? report.sortedCategories.first
            phase = .ready(report)
        }
    }

    private func progress(_ files: Int) {
        if case .scanning(let current) = phase, files > current { phase = .scanning(files: files) }
    }

    func cancel() {
        task?.cancel()
        phase = .idle
    }
}

// MARK: - Uninstaller

@MainActor
@Observable
final class UninstallerModel {
    enum Tab: String, CaseIterable { case installed = "Installed", leftovers = "Leftovers" }

    var tab: Tab = .installed
    var search = ""
    private(set) var apps: [InstalledApp] = []
    private(set) var loadingApps = false
    private(set) var selectedAppID: String?
    private(set) var plan: [Finding] = []
    private(set) var loadingPlan = false
    var planSelection: Set<UUID> = []
    let leftovers: FindingsTool

    let settings: AppSettings
    let cleanup: CleanupModel

    init(settings: AppSettings, cleanup: CleanupModel) {
        self.settings = settings
        self.cleanup = cleanup
        leftovers = FindingsTool(cleanup: cleanup)
    }

    var filteredApps: [InstalledApp] {
        let present = apps.filter { FileManager.default.fileExists(atPath: $0.url.path) }
        guard !search.isEmpty else { return present }
        return present.filter { $0.name.localizedCaseInsensitiveContains(search) || ($0.bundleID ?? "").localizedCaseInsensitiveContains(search) }
    }

    var selectedApp: InstalledApp? { apps.first { $0.id == selectedAppID } }

    func loadApps() {
        guard !loadingApps else { return }
        loadingApps = true
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                AppInventory.apps(in: AppInventory.liveFolders(),
                                  appGuard: AppBundleGuard(applicationFolders: AppInventory.liveFolders()))
            }.value
            apps = found
            loadingApps = false
            await measureSizes()
        }
    }

    private func measureSizes() async {
        let urls = apps.map(\.url)
        await withTaskGroup(of: (URL, Int64).self) { group in
            for url in urls {
                group.addTask { (url, SizeCalculator.measure(url)?.allocatedBytes ?? 0) }
            }
            for await (url, size) in group {
                if let index = apps.firstIndex(where: { $0.url == url }) { apps[index].sizeBytes = size }
            }
        }
    }

    func select(_ app: InstalledApp) {
        selectedAppID = app.id
        plan = []
        planSelection = []
        guard app.canUninstall else { return }
        loadingPlan = true
        let context = settings.makeContext()
        let others = apps
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                AppUninstallModule(context: context).plan(for: app, otherApps: others)
            }.value
            guard selectedAppID == app.id else { return }
            plan = found
            // The app itself plus Safe leftovers start checked.
            planSelection = Set(found.filter { $0.skipReason == nil && ($0.group == "Application" || $0.risk == .safe) }.map(\.id))
            loadingPlan = false
        }
    }

    var visiblePlan: [Finding] { plan.filter { !cleanup.removedIDs.contains($0.id) } }
    var selectedPlan: [Finding] { visiblePlan.filter { planSelection.contains($0.id) && $0.skipReason == nil } }

    func requestUninstall() {
        cleanup.requestClean(selectedPlan, permanent: false)
    }

    func scanLeftovers() {
        let context = settings.makeContext()
        leftovers.scan { await AppLeftoversModule(context: context).scan() }
    }

    static func icon(for app: InstalledApp) -> NSImage {
        NSWorkspace.shared.icon(forFile: app.url.path)
    }
}
