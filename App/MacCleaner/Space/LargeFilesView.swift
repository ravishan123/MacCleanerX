import CleanerCore
import SwiftUI

struct LargeFilesView: View {
    @Environment(AppModel.self) private var app

    private static let sizes: [(String, Int64)] = [
        ("10 MB", 10_000_000), ("50 MB", 50_000_000), ("100 MB", 100_000_000), ("500 MB", 500_000_000), ("1 GB", 1_000_000_000),
    ]
    private static let ages: [(String, TimeInterval?)] = [
        ("Off", nil), ("6 months", 182 * 86_400), ("1 year", 365 * 86_400), ("2 years", 730 * 86_400),
    ]

    var body: some View {
        @Bindable var app = app
        let tool = app.largeFiles
        VStack(spacing: 0) {
            ScreenHeader(
                label: "Space",
                title: "Large & old files.",
                subtitle: "In Documents, Downloads, Desktop, Movies, Music and Pictures. Nothing is pre-selected."
            ) {
                HStack(spacing: 10) {
                    Picker("Larger than", selection: $app.largeFileCriteria.minimumBytes) {
                        ForEach(Self.sizes, id: \.1) { Text($0.0).tag($0.1) }
                    }
                    .fixedSize()
                    Picker("Not opened in", selection: $app.largeFileCriteria.unusedFor) {
                        ForEach(Self.ages, id: \.0) { Text($0.0).tag($0.1) }
                    }
                    .fixedSize()
                    Button(tool.phase == .ready ? "Rescan" : "Scan") { scan() }
                        .buttonStyle(.pill)
                        .disabled(tool.phase == .scanning)
                }
                .font(.system(size: 12))
            }
            .padding(.horizontal, 48)
            .padding(.top, 52)
            .padding(.bottom, 24)

            Hairline()
            switch tool.phase {
            case .idle:
                ToolPlaceholder(title: "Find what's taking space",
                                message: "Big files, and files you haven't opened in a long time.",
                                action: "Scan", run: scan)
            case .scanning:
                ToolScanning(message: "Looking through your folders") { tool.cancel() }
            case .ready:
                if tool.visible.isEmpty {
                    ToolPlaceholder(title: "Nothing matches", message: "Try a smaller size or a shorter time.", action: "Scan again", run: scan)
                } else {
                    list(tool)
                }
            }
            ToolBottomBar(bytes: tool.selectedBytes, count: tool.selected.count) { tool.requestClean() }
        }
    }

    private func scan() {
        let context = app.settings.makeContext()
        let criteria = app.largeFileCriteria
        app.largeFiles.scan { await LargeOldFilesModule(context: context, criteria: criteria).scan() }
    }

    private func list(_ tool: FindingsTool) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(tool.groups(by: \.group), id: \.name) { group in
                    Section {
                        ForEach(group.items) { finding in
                            ToolRow(
                                finding: finding,
                                state: tool.selection.contains(finding.id) ? .on : .off,
                                isEnabled: tool.isSelectable(finding)
                            ) {
                                tool.setSelected([finding], !tool.selection.contains(finding.id))
                            } trailing: {
                                if let opened = finding.lastOpened {
                                    Text("OPENED " + opened.formatted(.relative(presentation: .named)).uppercased())
                                        .font(Typo.mono(9.5, .medium)).tracking(0.8).foregroundStyle(Theme.secondary)
                                }
                            }
                        }
                    } header: {
                        ToolGroupHeader(
                            name: group.name, detail: "\(group.items.count)",
                            bytes: group.items.reduce(0) { $0 + $1.reclaimableBytes },
                            state: tool.selectionState(group.items),
                            isEnabled: group.items.contains(where: tool.isSelectable)
                        ) { tool.setSelected(group.items, tool.selectionState(group.items) != .on) }
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.bottom, 12)
        }
    }
}

struct DuplicatesView: View {
    @Environment(AppModel.self) private var app
    @State private var blocked = false

    var body: some View {
        let tool = app.duplicates
        VStack(spacing: 0) {
            ScreenHeader(
                label: "Space",
                title: "Duplicates.",
                subtitle: "Exact copies, confirmed byte for byte. One copy of each file always stays."
            ) {
                HStack(spacing: 10) {
                    if tool.phase == .ready && !tool.visible.isEmpty {
                        Button("Select copies") { tool.selectAllButOldest() }
                            .buttonStyle(.pill)
                            .help("Selects every copy except the oldest one in each set.")
                    }
                    Button(tool.phase == .ready ? "Rescan" : "Scan") { scan() }
                        .buttonStyle(.pill)
                        .disabled(tool.phase == .scanning)
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 52)
            .padding(.bottom, 24)

            Hairline()
            switch tool.phase {
            case .idle:
                ToolPlaceholder(title: "Find exact copies",
                                message: "Files of 1 MB or more in your personal folders.",
                                action: "Scan", run: scan)
            case .scanning:
                ToolScanning(message: "Comparing files") { tool.cancel() }
            case .ready:
                if tool.visible.isEmpty {
                    ToolPlaceholder(title: "No duplicates", message: "No exact copies of 1 MB or more.", action: "Scan again", run: scan)
                } else {
                    list(tool)
                }
            }
            ToolBottomBar(bytes: tool.selectedBytes, count: tool.selected.count) { tool.requestClean() }
        }
        .alert("Keep at least one copy", isPresented: $blocked) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Every other copy of this file is already selected. One copy always stays.")
        }
    }

    private func scan() {
        let context = app.settings.makeContext()
        app.duplicates.scan { await DuplicatesModule(context: context).scan() }
    }

    private func list(_ tool: FindingsTool) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(tool.groups(by: { $0.duplicateSet ?? $0.displayPath }), id: \.name) { group in
                    Section {
                        ForEach(group.items.sorted { $0.displayPath < $1.displayPath }) { finding in
                            let isOn = tool.selection.contains(finding.id)
                            ToolRow(finding: finding, state: isOn ? .on : .off, isEnabled: tool.isSelectable(finding)) {
                                if isOn {
                                    tool.setSelected([finding], false)
                                } else if tool.canSelectCopy(finding) {
                                    tool.setSelected([finding], true)
                                } else {
                                    blocked = true
                                }
                            } trailing: {
                                if !isOn && !group.items.contains(where: { $0.id != finding.id && !tool.selection.contains($0.id) }) {
                                    Tag(text: "Keeps")
                                }
                                if let modified = finding.lastModified {
                                    Text(modified.formatted(date: .abbreviated, time: .omitted).uppercased())
                                        .font(Typo.mono(9.5, .medium)).foregroundStyle(Theme.secondary)
                                }
                            }
                        }
                    } header: {
                        VStack(spacing: 0) {
                            Hairline()
                            HStack(spacing: 14) {
                                Text(group.items.first?.group ?? "").font(Typo.bodyMedium).lineLimit(1)
                                Text("\(group.items.count) COPIES").font(Typo.mono(9.5, .medium)).tracking(1.1).foregroundStyle(Theme.secondary)
                                Spacer()
                                Text((group.items.first?.reclaimableBytes ?? 0).formattedBytes + " EACH")
                                    .font(Typo.mono(11, .medium))
                            }
                            .padding(.vertical, 12)
                        }
                        .background(Theme.background)
                    }
                }
            }
            .padding(.horizontal, 48)
            .padding(.bottom, 12)
        }
    }
}
