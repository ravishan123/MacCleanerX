import CleanerCore
import SwiftUI

struct CleanupView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let cleanup = app.cleanup
        VStack(spacing: 0) {
            ScreenHeader(
                label: "Cleanup",
                title: "Choose what goes.",
                subtitle: "Items go to the Trash unless you say otherwise."
            ) {
                if cleanup.phase == .scanning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("SCANNING").font(Typo.mono(10, .medium)).tracking(1.4).foregroundStyle(Theme.secondary)
                    }
                } else if !cleanup.allFindings.isEmpty || cleanup.phase == .ready {
                    Button("Rescan") { cleanup.scan() }
                        .buttonStyle(.pill)
                        .keyboardShortcut("r", modifiers: .command)
                        .disabled(cleanup.phase == .cleaning)
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 52)
            .padding(.bottom, 24)

            Hairline()

            if cleanup.phase == .idle && cleanup.allFindings.isEmpty {
                EmptyScan { cleanup.scan() }
            } else {
                HStack(spacing: 0) {
                    CategoryColumn().frame(width: 290)
                    Hairline(vertical: true)
                    if let category = cleanup.focusedCategory {
                        CategoryDetail(category: category)
                    }
                }
            }

            CleanupBottomBar()
        }
    }
}

private struct EmptyScan: View {
    let scan: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            DotRing(progress: 0, isActive: false, diameter: 120, dotCount: 40, dotSize: 3.5)
            VStack(spacing: 8) {
                Text("Nothing scanned yet").font(.system(size: 18, weight: .light))
                Text("Scanning only looks. Nothing is removed until you confirm.")
                    .font(Typo.body).foregroundStyle(Theme.secondary)
            }
            Button("Scan", action: scan)
                .buttonStyle(.pillPrimary)
                .keyboardShortcut(.defaultAction)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Categories

private struct CategoryColumn: View {
    @Environment(AppModel.self) private var app
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(Array(CleanupCategory.junkCases.enumerated()), id: \.element) { index, category in
                    CategoryRow(category: category, number: index + 1)
                }
            }
            .padding(16)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.space) {
            guard let category = app.cleanup.focusedCategory else { return .ignored }
            app.cleanup.toggle(app.cleanup.items(in: category))
            return .handled
        }
        .accessibilityLabel("Cleanup categories")
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        let all = CleanupCategory.junkCases
        let index = app.cleanup.focusedCategory.flatMap(all.firstIndex) ?? 0
        app.cleanup.focusedCategory = all[(index + delta + all.count) % all.count]
        return .handled
    }
}

private struct CategoryRow: View {
    @Environment(AppModel.self) private var app
    let category: CleanupCategory
    let number: Int

    var body: some View {
        let cleanup = app.cleanup
        let items = cleanup.items(in: category)
        let isFocused = cleanup.focusedCategory == category
        HStack(spacing: 12) {
            CheckButton(
                state: cleanup.selectionState(items),
                label: "Select all \(category.displayName)",
                isEnabled: items.contains(where: cleanup.isSelectable) && cleanup.phase != .cleaning
            ) { cleanup.toggle(items) }

            Button { cleanup.focusedCategory = category } label: {
                HStack(spacing: 10) {
                    Text(String(format: "%02d", number))
                        .font(Typo.mono(10, .medium))
                        .foregroundStyle(Theme.secondary)
                    Text(category.displayName)
                        .font(.system(size: 13, weight: isFocused ? .medium : .regular))
                    Spacer()
                    trailing(items)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(category.displayName)
            .accessibilityValue(cleanup.bytes(items).formattedBytes)
            .accessibilityAddTraits(isFocused ? .isSelected : [])
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 10).fill(isFocused ? Theme.surface : .clear))
    }

    @ViewBuilder
    private func trailing(_ items: [Finding]) -> some View {
        let cleanup = app.cleanup
        if !cleanup.loadedCategories.contains(category) {
            if cleanup.phase == .scanning {
                ProgressView().controlSize(.mini).accessibilityLabel("Scanning")
            } else {
                Text("—").font(Typo.mono(11)).foregroundStyle(Theme.secondary)
            }
        } else if cleanup.needsAccess(category) && items.count == 1 {
            HStack(spacing: 5) {
                Circle().fill(Theme.accent).frame(width: 5, height: 5)
                Text("NO ACCESS").font(Typo.mono(9.5, .semibold)).tracking(1)
            }
        } else {
            Text(cleanup.bytes(items).formattedBytes)
                .font(Typo.mono(11.5))
                .foregroundStyle(Theme.secondary)
        }
    }
}

// MARK: - Items

private struct CategoryDetail: View {
    @Environment(AppModel.self) private var app
    let category: CleanupCategory

    var body: some View {
        let cleanup = app.cleanup
        let groups = cleanup.groups(in: category)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(category.displayName).font(.system(size: 20, weight: .light))
                SectionLabel("By app")
                Spacer()
                let parts = cleanup.bytes(cleanup.items(in: category)).byteParts
                HStack(alignment: .bottom, spacing: 6) {
                    DotMatrixText(text: parts.value, dotSize: 3)
                    Text(parts.unit).font(Typo.mono(10, .medium)).foregroundStyle(Theme.secondary)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 16)

            if groups.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Text(cleanup.loadedCategories.contains(category) ? "Nothing to clean" : "Scanning…")
                        .font(.system(size: 16, weight: .light))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups, id: \.name) { group in
                            Section {
                                ForEach(group.items) { finding in
                                    FindingRow(finding: finding)
                                }
                            } header: {
                                GroupHeader(name: group.name, items: group.items)
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
                }
            }

            Hairline()
            Text(category.footnote)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
        }
    }
}

private struct GroupHeader: View {
    @Environment(AppModel.self) private var app
    let name: String
    let items: [Finding]

    var body: some View {
        let cleanup = app.cleanup
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 14) {
                CheckButton(
                    state: cleanup.selectionState(items),
                    label: "Select all items from \(name)",
                    isEnabled: items.contains(where: cleanup.isSelectable) && cleanup.phase != .cleaning
                ) { cleanup.toggle(items) }
                Text(name).font(Typo.bodyMedium)
                if items.count > 1 {
                    Text("\(items.count)").font(Typo.mono(10, .medium)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Text(cleanup.bytes(items).formattedBytes).font(Typo.mono(12, .medium))
            }
            .padding(.vertical, 12)
        }
        .background(Theme.background)
    }
}

private struct FindingRow: View {
    @Environment(AppModel.self) private var app
    let finding: Finding

    var body: some View {
        let cleanup = app.cleanup
        HStack(spacing: 14) {
            CheckToggle(
                isOn: Binding(
                    get: { cleanup.selection.contains(finding.id) },
                    set: { cleanup.setSelected([finding], $0) }
                ),
                label: finding.displayName,
                isEnabled: cleanup.isSelectable(finding) && cleanup.phase != .cleaning
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(finding.displayName).font(Typo.body).lineLimit(1)
                Text(displayPath)
                    .font(Typo.mono(10.5))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 12)

            if finding.skipReason == .needsFullDiskAccess {
                Button("Grant access") { app.settings.openFullDiskAccessSettings() }
                    .buttonStyle(.pillSmall)
            }
            if let reason = finding.skipReason {
                Tag(skip: reason).help(reason.explanation)
            }
            if finding.risk == .review { Tag(risk: .review) }
            if finding.requiresPermanentDeletion {
                Tag(text: "Permanent", signal: true).help("Can't go to the Trash. Removing it is permanent.")
            }
            Text(finding.skipReason == .needsFullDiskAccess ? "—" : finding.reclaimableBytes.formattedBytes)
                .font(Typo.mono(11.5))
                .foregroundStyle(cleanup.isSelectable(finding) ? Theme.primary : Theme.secondary)
                .frame(minWidth: 72, alignment: .trailing)
        }
        .padding(.leading, 31)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityValue)
        .contextMenu {
            if finding.url != nil {
                Button("Show in Finder") { cleanup.reveal(finding) }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(finding.displayPath, forType: .string)
                }
                Divider()
                Button("Never Clean This Item") { cleanup.exclude(finding) }
            }
        }
    }

    private var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = finding.displayPath
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private var accessibilityValue: String {
        var parts = [finding.reclaimableBytes.formattedBytes]
        if app.cleanup.selection.contains(finding.id) { parts.append("selected") }
        if let reason = finding.skipReason { parts.append(reason.explanation) }
        if finding.risk == .review { parts.append("review before removing") }
        if finding.requiresPermanentDeletion { parts.append("removal is permanent") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Bottom bar

private struct CleanupBottomBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var cleanup = app.cleanup
        let dryRun = app.settings.dryRun
        BottomBar {
            SelectionSummary(
                bytes: cleanup.selectedBytes,
                destination: dryRun ? "Dry run" : cleanup.permanentDelete ? "Deleted permanently" : "Trash"
            )
        } trailing: {
            if cleanup.phase == .cleaning {
                ProgressView().controlSize(.small)
            }
            Toggle(isOn: $cleanup.permanentDelete) {
                Text("Delete permanently").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(Theme.accent)
            .disabled(dryRun)
            .help("Skip the Trash. You'll be asked twice.")

            Button(title(dryRun: dryRun, permanent: cleanup.permanentDelete)) { cleanup.requestClean() }
                .buttonStyle(cleanup.permanentDelete && !dryRun ? .pillDestructive : .pillPrimary)
                .disabled(cleanup.selectedFindings.isEmpty || cleanup.phase == .cleaning || cleanup.phase == .scanning)
        }
    }

    private func title(dryRun: Bool, permanent: Bool) -> String {
        if dryRun { return "Simulate" }
        return permanent ? "Delete permanently…" : "Move to Trash"
    }
}
