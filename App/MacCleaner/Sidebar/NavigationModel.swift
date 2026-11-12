import Observation
import SwiftUI

enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
    case smartCare, cleanup, storage, largeFiles, duplicates, uninstaller, protection, performance, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartCare: "Smart Care"
        case .cleanup: "Cleanup"
        case .storage: "Storage"
        case .largeFiles: "Large & old files"
        case .duplicates: "Duplicates"
        case .uninstaller: "Uninstaller"
        case .protection: "Protection"
        case .performance: "Performance"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .smartCare: "checkmark.circle"
        case .cleanup: "trash"
        case .storage: "chart.bar"
        case .largeFiles: "doc.badge.clock"
        case .duplicates: "square.on.square"
        case .uninstaller: "app.badge.checkmark"
        case .protection: "shield"
        case .performance: "gauge.with.dots.needle.33percent"
        case .settings: "gearshape"
        }
    }

    /// Protection and Performance are placeholders for a later version.
    var isAvailable: Bool {
        switch self {
        case .protection, .performance: false
        default: true
        }
    }
}

@MainActor
@Observable
final class NavigationModel {
    var selection: SidebarItem? = .smartCare
    var settingsTab: SettingsTab = .general

    func showActivityLog() {
        settingsTab = .activity
        selection = .settings
    }
}
