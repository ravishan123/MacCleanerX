import CleanerCore
import SwiftUI

struct StorageView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let storage = app.storage
        VStack(spacing: 0) {
            ScreenHeader(
                label: "Storage",
                title: "Where your space goes.",
                subtitle: "Measures your home folder and Applications. Nothing is changed."
            ) {
                if case .ready = storage.phase {
                    Button("Measure again") { storage.scan() }.buttonStyle(.pill)
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, 52)
            .padding(.bottom, 24)

            switch storage.phase {
            case .idle:
                Hairline()
                ToolPlaceholder(
                    title: "See what fills your disk",
                    message: "Documents, photos, videos, apps, caches and more. This can take a minute.",
                    action: "Measure"
                ) { storage.scan() }
            case .scanning(let files):
                Hairline()
                ToolScanning(message: "Counted \(files.formatted()) files") { storage.cancel() }
            case .ready(let report):
                StorageReportView(report: report)
            }
        }
    }
}

private struct StorageReportView: View {
    @Environment(AppModel.self) private var app
    let report: StorageReport

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let used = report.used.byteParts
            HStack(alignment: .bottom, spacing: 12) {
                DotMatrixText(text: used.value, dotSize: 6)
                Text(used.unit + " USED").font(Typo.mono(12, .medium)).tracking(1.2).foregroundStyle(Theme.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    StatusLine(label: "Free", value: report.volumeAvailable.formattedBytes)
                    StatusLine(label: "Disk", value: report.volumeTotal.formattedBytes)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(report.used.formattedBytes) used of \(report.volumeTotal.formattedBytes). \(report.volumeAvailable.formattedBytes) free.")
            .padding(.horizontal, 48)

            DotBar(report: report, highlighted: app.storage.focused)
                .padding(.horizontal, 48)
                .padding(.top, 20)
                .padding(.bottom, 24)

            Hairline()
            HStack(spacing: 0) {
                CategoryList(report: report).frame(width: 340)
                Hairline(vertical: true)
                if let category = app.storage.focused {
                    CategoryItems(report: report, category: category)
                } else {
                    Spacer()
                }
            }
        }
    }
}

/// The whole disk as a grid of dots: black = used, grey = free, red = the
/// selected category.
private struct DotBar: View {
    let report: StorageReport
    let highlighted: StorageCategory?
    @Environment(\.colorScheme) private var colorScheme

    private let columns = 100
    private let rows = 4

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, _ in draw(in: &context, width: proxy.size.width) }
                .id(colorScheme)
        }
        .frame(height: 4 * 11)
        .accessibilityHidden(true)
    }

    private enum Owner { case category(StorageCategory), system, free }

    /// Which dots belong to which category: largest first, then System & other.
    private func owners(dots: Int) -> [Owner] {
        let perDot: Double = Double(max(report.volumeTotal, 1)) / Double(dots)
        var result: [Owner] = []
        for category in report.sortedCategories {
            let count: Int = Int((Double(report.bytes(category)) / perDot).rounded())
            result += Array(repeating: Owner.category(category), count: max(0, min(count, dots - result.count)))
        }
        let usedDots: Int = Int((Double(report.used) / perDot).rounded())
        if usedDots > result.count {
            result += Array(repeating: Owner.system, count: min(usedDots, dots) - result.count)
        }
        result += Array(repeating: Owner.free, count: max(0, dots - result.count))
        return result
    }

    private func color(for owner: Owner) -> Color {
        switch owner {
        case .category(let category): category == highlighted ? Theme.accent : Theme.primary
        case .system: Theme.secondary
        case .free: Theme.dotOff
        }
    }

    private func draw(in context: inout GraphicsContext, width: CGFloat) {
        let cell: CGFloat = width / CGFloat(columns)
        let dot: CGFloat = min(cell * 0.62, 6)
        let inset: CGFloat = (cell - dot) / 2
        for (index, owner) in owners(dots: columns * rows).enumerated() {
            let x: CGFloat = CGFloat(index / rows) * cell + inset
            let y: CGFloat = CGFloat(index % rows) * cell + inset
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: dot, height: dot)), with: .color(color(for: owner)))
        }
    }
}

private struct CategoryList: View {
    @Environment(AppModel.self) private var app
    let report: StorageReport

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(report.sortedCategories, id: \.self) { category in
                    row(category)
                }
                systemRow
            }
            .padding(16)
        }
    }

    private func row(_ category: StorageCategory) -> some View {
        let selected = app.storage.focused == category
        let bytes = report.bytes(category)
        return Button { app.storage.focused = category } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    if selected {
                        Circle().fill(Theme.accent).frame(width: 6, height: 6)
                    }
                    Text(category.displayName).font(.system(size: 13, weight: selected ? .medium : .regular))
                    Spacer()
                    Text(bytes.formattedBytes).font(Typo.mono(11.5)).foregroundStyle(Theme.secondary)
                }
                ProportionLine(fraction: Double(bytes) / Double(max(report.used, 1)), highlighted: selected)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Theme.surface : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.displayName)
        .accessibilityValue("\(bytes.formattedBytes), \(Int(Double(bytes) / Double(max(report.used, 1)) * 100)) percent of used space")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var systemRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("System & other").font(Typo.body).foregroundStyle(Theme.secondary)
                Spacer()
                Text(report.systemAndOther.formattedBytes).font(Typo.mono(11.5)).foregroundStyle(Theme.secondary)
            }
            ProportionLine(fraction: Double(report.systemAndOther) / Double(max(report.used, 1)), highlighted: false)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .help("macOS itself, other users, snapshots and folders Mac Cleaner can't read.")
        .accessibilityElement(children: .combine)
    }
}

private struct ProportionLine: View {
    let fraction: Double
    let highlighted: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline)
                Capsule().fill(highlighted ? Theme.accent : Theme.primary)
                    .frame(width: max(2, proxy.size.width * min(1, fraction)))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

private struct CategoryItems: View {
    @Environment(AppModel.self) private var app
    @Environment(NavigationModel.self) private var navigation
    let report: StorageReport
    let category: StorageCategory

    var body: some View {
        let usage = report.usage[category] ?? StorageUsage()
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(category.displayName).font(.system(size: 20, weight: .light))
                SectionLabel("\(usage.fileCount.formatted()) files")
                Spacer()
                if let destination {
                    Button(destination.title) { navigation.selection = destination.item }
                        .buttonStyle(.pillSmall)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 12)

            SectionLabel("Largest").padding(.horizontal, 28).padding(.bottom, 6)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(usage.largest) { item in
                        Hairline()
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.url.lastPathComponent).font(Typo.body).lineLimit(1)
                                Text(ToolRow<EmptyView>.shortPath(item.url.path))
                                    .font(Typo.mono(10.5)).foregroundStyle(Theme.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 12)
                            Text(item.bytes.formattedBytes).font(Typo.mono(11.5))
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([item.url])
                            } label: {
                                Image(systemName: "arrow.up.forward").font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.pillQuiet)
                            .help("Show in Finder")
                            .accessibilityLabel("Show \(item.url.lastPathComponent) in Finder")
                        }
                        .padding(.vertical, 9)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, 28)
            }
            if report.unreadableFolders > 0 {
                Hairline()
                HStack(spacing: 8) {
                    Circle().fill(Theme.accent).frame(width: 5, height: 5)
                    Text("\(report.unreadableFolders) folders couldn't be read. Full Disk Access lets Mac Cleaner measure them.")
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
            }
        }
    }

    private var destination: (title: String, item: SidebarItem)? {
        switch category {
        case .cachesAndLogs, .trash, .iosBackups, .mail, .developer: ("Open Cleanup", .cleanup)
        case .documents, .images, .videos, .audio, .archives, .other: ("Find large files", .largeFiles)
        case .apps, .appData: ("Open Uninstaller", .uninstaller)
        }
    }
}
