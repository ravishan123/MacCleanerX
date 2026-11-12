import AppKit
import CleanerCore
import Observation

/// App-wide settings and services: database, exclusions, Full Disk Access
/// status, dry-run mode and the activity log.
@MainActor
@Observable
final class AppSettings {
    private static let dryRunKey = "dryRunMode"

    let database: AppDatabase?
    let databaseError: String?

    var dryRun: Bool {
        didSet { UserDefaults.standard.set(dryRun, forKey: Self.dryRunKey) }
    }
    private(set) var exclusions: [Exclusion] = []
    private(set) var fullDiskAccess: FullDiskAccess.Status = .unknown
    private(set) var activity: [ActionLogEntry] = []

    init() {
        do {
            database = try AppDatabase.openDefault()
            databaseError = nil
        } catch {
            database = nil
            databaseError = "The activity log and exclusions can't be saved: \(error.localizedDescription)"
        }
        dryRun = UserDefaults.standard.bool(forKey: Self.dryRunKey)
        reloadExclusions()
        reloadActivity()
        refreshFullDiskAccess()
    }

    /// A live context that honours the current exclusions.
    func makeContext() -> ModuleContext {
        ModuleContext.live(exclusions: exclusions.map(\.url))
    }

    func refreshFullDiskAccess() {
        fullDiskAccess = FullDiskAccess.status()
    }

    func reloadExclusions() {
        exclusions = (try? database?.exclusions()) ?? []
    }

    func addExclusion(_ url: URL) {
        try? database?.addExclusion(url)
        reloadExclusions()
    }

    func removeExclusion(_ exclusion: Exclusion) {
        try? database?.removeExclusion(path: exclusion.path)
        reloadExclusions()
    }

    func reloadActivity() {
        activity = (try? database?.recentActions(limit: 1000)) ?? []
    }

    func clearActivity() {
        try? database?.clearActionLog()
        reloadActivity()
    }

    func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(FullDiskAccess.settingsURL)
    }
}
