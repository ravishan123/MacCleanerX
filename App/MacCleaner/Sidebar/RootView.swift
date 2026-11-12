import CleanerCore
import SwiftUI

struct RootView: View {
    @Environment(NavigationModel.self) private var navigation
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var navigation = navigation
        @Bindable var cleanup = app.cleanup
        @Bindable var app = app

        HStack(spacing: 0) {
            SidebarView(selection: $navigation.selection)
            Hairline(vertical: true)
            Group {
                switch navigation.selection ?? .smartCare {
                case .smartCare: SmartCareView()
                case .cleanup: CleanupView()
                case .storage: StorageView()
                case .largeFiles: LargeFilesView()
                case .duplicates: DuplicatesView()
                case .uninstaller: UninstallerView()
                case .settings: SettingsView()
                case .protection, .performance: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .foregroundStyle(Theme.primary)
        // One confirmation flow for every screen: nothing is removed without it.
        .cleanConfirmation(plan: $cleanup.pendingPlan) { plan in
            Task { await app.cleanup.perform(plan) }
        }
        .sheet(item: $cleanup.outcome) { outcome in
            CleanOutcomeSheet(outcome: outcome) { navigation.showActivityLog() }
        }
        .sheet(isPresented: $app.showOnboarding) {
            OnboardingView().interactiveDismissDisabled()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.settings.refreshFullDiskAccess()
        }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @FocusState private var focused: Bool

    private let main: [SidebarItem] = [.smartCare, .cleanup]
    private let space: [SidebarItem] = [.storage, .largeFiles, .duplicates]
    private let apps: [SidebarItem] = [.uninstaller]
    private let later: [SidebarItem] = [.protection, .performance]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DotMatrixText(text: "MAC CLEANER", dotSize: 1.7)
                .padding(.horizontal, 12)
                .padding(.top, 52)
                .padding(.bottom, 30)

            section(nil, main, from: 1)
            section("Space", space, from: 3)
            section("Apps", apps, from: 6)
            section("Later", later, from: 7)

            Spacer()
            row(.settings, number: nil)
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 12)
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        .background(Theme.background)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.upArrow) { move(-1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sections")
    }

    @ViewBuilder
    private func section(_ title: String?, _ items: [SidebarItem], from first: Int) -> some View {
        if let title {
            SectionLabel(title)
                .padding(.horizontal, 12)
                .padding(.top, 22)
                .padding(.bottom, 6)
        }
        VStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                row(item, number: first + index)
            }
        }
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        let order = SidebarItem.allCases.filter(\.isAvailable)
        guard let current = selection, let index = order.firstIndex(of: current) else { return .ignored }
        selection = order[(index + delta + order.count) % order.count]
        return .handled
    }

    private func row(_ item: SidebarItem, number: Int?) -> some View {
        let isSelected = selection == item
        return Button { selection = item } label: {
            HStack(spacing: 12) {
                Text(number.map { String(format: "%02d", $0) } ?? "  ")
                    .font(Typo.mono(10, .medium))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 18, alignment: .leading)
                Text(item.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(item.isAvailable ? Theme.primary : Theme.secondary)
                Spacer()
                if isSelected {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6).accessibilityHidden(true)
                } else if !item.isAvailable {
                    Text("SOON").font(Typo.mono(9, .medium)).tracking(1.2).foregroundStyle(Theme.secondary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10).fill(isSelected ? Theme.surface : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!item.isAvailable)
        .accessibilityLabel(item.isAvailable ? item.title : "\(item.title), coming later")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(item.isAvailable ? item.title : "Coming in a later version")
    }
}
