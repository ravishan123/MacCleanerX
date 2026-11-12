import CleanerCore
import SwiftUI

/// A checkbox row for a finding on a tool screen.
struct ToolRow<Trailing: View>: View {
    let finding: Finding
    let state: TriState
    var isEnabled = true
    let toggle: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            CheckButton(state: state, label: finding.displayName, isEnabled: isEnabled, action: toggle)
            VStack(alignment: .leading, spacing: 3) {
                Text(finding.displayName).font(Typo.body).lineLimit(1)
                Text(Self.shortPath(finding.displayPath))
                    .font(Typo.mono(10.5))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 12)
            trailing
            if let reason = finding.skipReason { Tag(skip: reason).help(reason.explanation) }
            if finding.risk == .review { Tag(risk: .review) }
            Text(finding.reclaimableBytes.formattedBytes)
                .font(Typo.mono(11.5))
                .frame(minWidth: 72, alignment: .trailing)
        }
        .padding(.leading, 31)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .contextMenu {
            if let url = finding.url {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(finding.displayPath, forType: .string)
                }
            }
        }
    }

    static func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

struct ToolGroupHeader: View {
    let name: String
    let detail: String?
    let bytes: Int64
    let state: TriState
    var isEnabled = true
    let toggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 14) {
                CheckButton(state: state, label: "Select all in \(name)", isEnabled: isEnabled, action: toggle)
                Text(name).font(Typo.bodyMedium).lineLimit(1)
                if let detail {
                    Text(detail.uppercased()).font(Typo.mono(9.5, .medium)).tracking(1.1).foregroundStyle(Theme.secondary)
                }
                Spacer()
                Text(bytes.formattedBytes).font(Typo.mono(12, .medium))
            }
            .padding(.vertical, 12)
        }
        .background(Theme.background)
    }
}

/// Centered placeholder with a dot ring, used before the first scan.
struct ToolPlaceholder: View {
    let title: String
    let message: String
    let action: String
    let run: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            DotRing(progress: 0, isActive: false, diameter: 120, dotCount: 40, dotSize: 3.5)
            VStack(spacing: 8) {
                Text(title).font(.system(size: 18, weight: .light))
                Text(message).font(Typo.body).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
            }
            Button(action, action: run)
                .buttonStyle(.pillPrimary)
                .keyboardShortcut(.defaultAction)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 48)
    }
}

/// Spinning dot ring for scans without a known total.
struct ToolScanning: View {
    let message: String
    var cancel: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                DotRing(progress: reduceMotion ? 0.25 : (t / 2.4).truncatingRemainder(dividingBy: 1),
                        isActive: true, diameter: 120, dotCount: 40, dotSize: 3.5)
            }
            Text(message.uppercased())
                .font(Typo.mono(10, .medium)).tracking(1.6).foregroundStyle(Theme.secondary)
                .accessibilityAddTraits(.updatesFrequently)
            if let cancel {
                Button("Stop", action: cancel).buttonStyle(.pillSmall).keyboardShortcut(.cancelAction)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Bottom bar shared by the tools: everything goes to the Trash.
struct ToolBottomBar: View {
    @Environment(AppModel.self) private var app
    let bytes: Int64
    let count: Int
    var title = "Move to Trash"
    let action: () -> Void

    var body: some View {
        BottomBar {
            SelectionSummary(bytes: bytes, destination: app.settings.dryRun ? "Dry run" : "Trash")
        } trailing: {
            if app.cleanup.phase == .cleaning { ProgressView().controlSize(.small) }
            Button(app.settings.dryRun ? "Simulate" : title, action: action)
                .buttonStyle(.pillPrimary)
                .disabled(count == 0 || app.cleanup.phase == .cleaning)
        }
    }
}
