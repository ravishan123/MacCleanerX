import CleanerCore
import SwiftUI

struct UninstallerView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var model = app.uninstaller
        VStack(spacing: 0) {
            ScreenHeader(
                label: "Apps",
                title: "Uninstaller.",
                subtitle: "Remove apps together with the files they leave behind. Apps go to the Trash."
            ) {
                HStack(spacing: 24) {
                    ForEach(UninstallerModel.Tab.allCases, id: \.self) { tab in
                        let active = model.tab == tab
                        Button { model.tab = tab } label: {
                            HStack(spacing: 7) {
                                Circle().fill(active ? Theme.accent : .clear).frame(width: 5, height: 5)
                                Text(tab.rawValue.uppercased()).font(Typo.mono(11, .medium)).tracking(1.6)
                                    .foregroundStyle(active ? Theme.primary : Theme.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(active ? .isSelected : [])
                    }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 48)
            .padding(.top, 52)
            .padding(.bottom, 24)

            Hairline()
            switch model.tab {
            case .installed: InstalledAppsView()
            case .leftovers: LeftoversView()
            }
        }
        .onAppear { if model.apps.isEmpty { model.loadApps() } }
    }
}

private struct InstalledAppsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var model = app.uninstaller
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                        TextField("Search apps", text: $model.search)
                            .textFieldStyle(.plain)
                            .font(Typo.body)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    Hairline()
                    if model.loadingApps {
                        ToolScanning(message: "Finding apps")
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(model.filteredApps) { installed in
                                    AppRow(installed: installed)
                                }
                            }
                            .padding(12)
                        }
                    }
                }
                .frame(width: 320)
                Hairline(vertical: true)
                if let selected = model.selectedApp {
                    AppDetail(installed: selected)
                } else {
                    VStack(spacing: 8) {
                        Spacer()
                        Text("Choose an app").font(.system(size: 18, weight: .light))
                        Text("See what it installed before removing anything.").font(Typo.body).foregroundStyle(Theme.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            ToolBottomBar(
                bytes: model.selectedPlan.reduce(0) { $0 + $1.reclaimableBytes },
                count: model.selectedPlan.count,
                title: "Uninstall"
            ) { model.requestUninstall() }
        }
    }
}

private struct AppRow: View {
    @Environment(AppModel.self) private var app
    let installed: InstalledApp

    var body: some View {
        let model = app.uninstaller
        let selected = model.selectedAppID == installed.id
        Button { model.select(installed) } label: {
            HStack(spacing: 12) {
                Image(nsImage: UninstallerModel.icon(for: installed))
                    .resizable()
                    .frame(width: 26, height: 26)
                    .opacity(installed.canUninstall ? 1 : 0.5)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(installed.name).font(.system(size: 13, weight: selected ? .medium : .regular)).lineLimit(1)
                        .foregroundStyle(installed.canUninstall ? Theme.primary : Theme.secondary)
                    if let version = installed.version {
                        Text(version).font(Typo.mono(9.5)).foregroundStyle(Theme.secondary)
                    }
                }
                Spacer()
                if !installed.canUninstall {
                    Image(systemName: "lock").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                        .help(installed.blockReason ?? "")
                }
                Text(installed.sizeBytes.map(\.formattedBytes) ?? "…").font(Typo.mono(11)).foregroundStyle(Theme.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Theme.surface : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(installed.name)
        .accessibilityValue([installed.sizeBytes?.formattedBytes, installed.blockReason].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct AppDetail: View {
    @Environment(AppModel.self) private var app
    let installed: InstalledApp

    var body: some View {
        let model = app.uninstaller
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Image(nsImage: UninstallerModel.icon(for: installed))
                    .resizable().frame(width: 56, height: 56).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(installed.name).font(.system(size: 22, weight: .light))
                    Text(installed.bundleID ?? installed.url.path).font(Typo.mono(10.5)).foregroundStyle(Theme.secondary)
                    StatusLine(label: "Signature", value: installed.signature.displayName,
                               signal: !installed.signature.isTrustedDeveloper)
                }
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)

            Hairline()
            if let reason = installed.blockReason {
                HStack(spacing: 10) {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                    Text("Mac Cleaner can't remove this app: \(reason)").font(Typo.body)
                }
                .padding(28)
                Spacer()
            } else if model.loadingPlan {
                ToolScanning(message: "Finding files")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groups(model.visiblePlan), id: \.name) { group in
                            Hairline()
                            SectionLabel(group.name).padding(.top, 14).padding(.bottom, 2)
                            ForEach(group.items) { finding in
                                ToolRow(
                                    finding: finding,
                                    state: model.planSelection.contains(finding.id) ? .on : .off,
                                    isEnabled: finding.skipReason == nil
                                ) {
                                    if model.planSelection.contains(finding.id) {
                                        model.planSelection.remove(finding.id)
                                    } else {
                                        model.planSelection.insert(finding.id)
                                    }
                                } trailing: { EmptyView() }
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
                }
                if model.visiblePlan.isEmpty {
                    Text("Removed.").font(.system(size: 16, weight: .light)).padding(28)
                    Spacer()
                }
            }
        }
    }

    private func groups(_ items: [Finding]) -> [(name: String, items: [Finding])] {
        let order = ["Application", "Application Support", "App container", "Shared container", "Preferences", "Caches",
                     "Saved window state", "Web data", "Cookies", "Logs", "Scripts", "Startup items"]
        return Dictionary(grouping: items, by: \.group)
            .map { (name: $0.key, items: $0.value) }
            .sorted { (order.firstIndex(of: $0.name) ?? 99) < (order.firstIndex(of: $1.name) ?? 99) }
    }
}

private struct LeftoversView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let model = app.uninstaller
        let tool = model.leftovers
        VStack(spacing: 0) {
            switch tool.phase {
            case .idle:
                ToolPlaceholder(title: "Files of deleted apps",
                                message: "Settings and support files named after apps that are no longer installed.",
                                action: "Scan") { model.scanLeftovers() }
            case .scanning:
                ToolScanning(message: "Checking ~/Library") { tool.cancel() }
            case .ready:
                if tool.visible.isEmpty {
                    ToolPlaceholder(title: "No leftovers", message: "Nothing left behind by deleted apps.", action: "Scan again") { model.scanLeftovers() }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                            ForEach(tool.groups(by: \.group), id: \.name) { group in
                                Section {
                                    ForEach(group.items) { finding in
                                        ToolRow(finding: finding, state: tool.selection.contains(finding.id) ? .on : .off,
                                                isEnabled: tool.isSelectable(finding)) {
                                            tool.setSelected([finding], !tool.selection.contains(finding.id))
                                        } trailing: { EmptyView() }
                                    }
                                } header: {
                                    ToolGroupHeader(
                                        name: group.name, detail: nil,
                                        bytes: group.items.reduce(0) { $0 + $1.reclaimableBytes },
                                        state: tool.selectionState(group.items)
                                    ) { tool.setSelected(group.items, tool.selectionState(group.items) != .on) }
                                }
                            }
                        }
                        .padding(.horizontal, 48)
                        .padding(.bottom, 12)
                    }
                }
            }
            ToolBottomBar(bytes: tool.selectedBytes, count: tool.selected.count) { tool.requestClean() }
        }
    }
}
