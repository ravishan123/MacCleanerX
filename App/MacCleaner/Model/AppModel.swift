import CleanerCore
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    let cleanup: CleanupModel
    let smartCare: SmartCareModel
    let storage = StorageModel()
    let largeFiles: FindingsTool
    let duplicates: FindingsTool
    let uninstaller: UninstallerModel
    var largeFileCriteria = LargeOldFilesModule.Criteria()
    var showOnboarding: Bool

    private static let onboardingKey = "onboardingCompleted"

    init() {
        let settings = AppSettings()
        let cleanup = CleanupModel(settings: settings)
        self.settings = settings
        self.cleanup = cleanup
        self.smartCare = SmartCareModel(settings: settings, cleanup: cleanup)
        self.largeFiles = FindingsTool(cleanup: cleanup)
        self.duplicates = FindingsTool(cleanup: cleanup)
        self.uninstaller = UninstallerModel(settings: settings, cleanup: cleanup)
        showOnboarding = !UserDefaults.standard.bool(forKey: Self.onboardingKey)
            || settings.fullDiskAccess == .denied
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        showOnboarding = false
    }
}
