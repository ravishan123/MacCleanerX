import CleanerCore
import SwiftUI
import UniformTypeIdentifiers

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case exclusions = "Exclusions"
    case activity = "Activity"
    case about = "About"
    var id: String { rawValue }
}

struct SettingsView: View {
    @Environment(NavigationModel.self) private var navigation

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader(label: "Settings", title: "Preferences.", subtitle: "Removal options, access, exclusions and history.")
                .padding(.bottom, 28)

            HStack(spacing: 28) {
                ForEach(SettingsTab.allCases) { tab in
                    let active = navigation.settingsTab == tab
                    Button { navigation.settingsTab = tab } label: {
                        HStack(spacing: 7) {
                            Circle().fill(active ? Theme.accent : .clear).frame(width: 5, height: 5)
                            Text(tab.rawValue.uppercased())
                                .font(Typo.mono(11, .medium))
                                .tracking(1.6)
                                .foregroundStyle(active ? Theme.primary : Theme.secondary)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
            Hairline()
                .padding(.bottom, 8)

            switch navigation.settingsTab {
            case .general: GeneralSettings()
            case .exclusions: ExclusionSettings()
            case .activity: ActivityLogView()
            case .about: AboutView()
            }
        }
        .padding(.horizontal, 48)
        .padding(.top, 52)
        .padding(.bottom, 24)
    }
}

/// A settings row: title and explanation on the left, control on the right.
private struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Typo.bodyMedium)
                    if let detail {
                        Text(detail).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                control
            }
            .padding(.vertical, 18)
            Hairline()
        }
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var settings = app.settings
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Removal").padding(.top, 20).padding(.bottom, 4)
                SettingRow(title: "Dry-run mode",
                           detail: "Cleanups only record what would be removed. Nothing is moved or deleted.") {
                    Toggle("Dry-run mode", isOn: $settings.dryRun).labelsHidden().toggleStyle(.switch)
                }
                SettingRow(title: "Default action",
                           detail: "“Delete permanently” can be switched on for one cleanup at a time. It's always off when Mac Cleaner starts, and always asks twice.") {
                    Text("MOVE TO TRASH").font(Typo.mono(11, .medium)).tracking(1.2)
                }

                SectionLabel("Access").padding(.top, 32).padding(.bottom, 4)
                SettingRow(title: "Full Disk Access",
                           detail: "Needed to check the Trash, Mail attachments and some caches.") {
                    FullDiskAccessStatus()
                }
                HStack(spacing: 10) {
                    Button("Open System Settings") { app.settings.openFullDiskAccessSettings() }.buttonStyle(.pillSmall)
                    Button("Check again") { app.settings.refreshFullDiskAccess() }.buttonStyle(.pillSmall)
                    Button("Show welcome") { app.showOnboarding = true }.buttonStyle(.pillSmall)
                }
                .padding(.top, 16)

                if let error = app.settings.databaseError {
                    HStack(spacing: 8) {
                        Circle().fill(Theme.accent).frame(width: 6, height: 6)
                        Text(error).font(.system(size: 12))
                    }
                    .padding(.top, 24)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
        }
    }
}

private struct ExclusionSettings: View {
    @Environment(AppModel.self) private var app
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Never offered or removed, including anything inside.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                Spacer()
                Button("Add…") { importing = true }.buttonStyle(.pillSmall)
            }
            .padding(.vertical, 16)
            Hairline()

            if app.settings.exclusions.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No exclusions").font(.system(size: 16, weight: .light))
                    Text("Add items here, or right-click an item in Cleanup and choose “Never Clean This Item”.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(app.settings.exclusions) { exclusion in
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(exclusion.url.lastPathComponent).font(Typo.body)
                                    Text(exclusion.path).font(Typo.mono(10.5)).foregroundStyle(Theme.secondary)
                                        .lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                Button("Remove") { app.settings.removeExclusion(exclusion) }
                                    .buttonStyle(.pillQuiet)
                                    .accessibilityLabel("Remove \(exclusion.url.lastPathComponent) from exclusions")
                            }
                            .padding(.vertical, 12)
                            Hairline()
                        }
                    }
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item, .folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { urls.forEach(app.settings.addExclusion) }
        }
    }
}

struct ActivityLogView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Everything moved, deleted, simulated or skipped.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                Spacer()
                Button("Refresh") { app.settings.reloadActivity() }.buttonStyle(.pillSmall)
                Button("Clear…") { confirmClear = true }
                    .buttonStyle(.pillSmall)
                    .disabled(app.settings.activity.isEmpty)
            }
            .padding(.vertical, 16)
            Hairline()

            if app.settings.activity.isEmpty {
                VStack {
                    Spacer()
                    Text("No activity yet").font(.system(size: 16, weight: .light))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(app.settings.activity) { entry in
                            ActivityRow(entry: entry)
                            Hairline()
                        }
                    }
                }
            }
        }
        .onAppear { app.settings.reloadActivity() }
        .confirmationDialog("Clear the activity log?", isPresented: $confirmClear) {
            Button("Clear Log", role: .destructive) { app.settings.clearActivity() }
        } message: {
            Text("This removes the history only. Items already in the Trash stay there.")
        }
    }
}

private struct ActivityRow: View {
    let entry: ActionLogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(entry.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                .font(Typo.mono(10.5))
                .foregroundStyle(Theme.secondary)
                .frame(width: 110, alignment: .leading)
            HStack(spacing: 6) {
                Circle().fill(entry.outcome == .skipped ? Theme.accent : entry.outcome == .simulated ? Theme.tertiary : Theme.primary)
                    .frame(width: 5, height: 5)
                Text(label.uppercased()).font(Typo.mono(9.5, .semibold)).tracking(1.1)
            }
            .frame(width: 120, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.target).font(Typo.mono(11)).lineLimit(1).truncationMode(.middle)
                    .help(entry.trashedPath.map { "\(entry.target)\nNow in the Trash: \($0)" } ?? entry.target)
                if let detail = entry.detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            Text(entry.category.displayName).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            Text(entry.bytes > 0 ? entry.bytes.formattedBytes : "—")
                .font(Typo.mono(11))
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        switch entry.outcome {
        case .movedToTrash: "Trashed"
        case .deleted: "Deleted"
        case .simulated: "Dry run"
        case .skipped: "Skipped"
        }
    }
}

private struct AboutView: View {
    var body: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DotMatrixText(text: "MAC CLEANER", dotSize: 4)
                    .padding(.top, 28)
                StatusLine(label: "Version", value: version)
                StatusLine(label: "Created by", value: "Ravishan Lakshitha")
                Text("Open source under the MIT License. Designed and developed by Ravishan Lakshitha, with help from the Mac Cleaner contributors.")
                    .font(Typo.body)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Link("Source code", destination: URL(string: "https://github.com/ravishan123/MacCleanerX")!)
                    Link("Report an issue", destination: URL(string: "https://github.com/ravishan123/MacCleanerX/issues")!)
                    Link("Developer on GitHub", destination: URL(string: "https://github.com/ravishan123")!)
                }
                .buttonStyle(.pillSmall)
                Text("Use at your own risk. Mac Cleaner only touches your own files, moves items to the Trash by default and always asks before removing anything, but no cleaner can guarantee that removing a file is harmless. Keep a backup, for example with Time Machine.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(SecurityReport.disclaimer)
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
