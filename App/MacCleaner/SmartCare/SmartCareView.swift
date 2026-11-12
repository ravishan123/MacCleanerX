import CleanerCore
import SwiftUI

struct SmartCareView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.smartCare.phase {
        case .idle, .scanning: SmartCareScanView()
        case .results(let report): SmartCareResultsView(report: report)
        }
    }
}

// MARK: - Ready / scanning

private struct SmartCareScanView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var smartCare = app.smartCare
        VStack(spacing: 0) {
            ScreenHeader(
                label: "Smart Care",
                title: "One scan. Everything checked.",
                subtitle: "Junk, warning signs and performance. Nothing changes until you confirm."
            )

            Spacer(minLength: 20)
            ScanDial()
            Text(caption.uppercased())
                .font(Typo.mono(10, .medium))
                .tracking(1.6)
                .foregroundStyle(Theme.secondary)
                .padding(.top, 28)
                .accessibilityAddTraits(.updatesFrequently)
            Spacer(minLength: 20)

            HStack(spacing: 12) {
                ScopeChip(number: "01", title: "System junk", detail: "Cache, logs, temp, Trash, Xcode", isOn: $smartCare.includeJunk)
                ScopeChip(number: "02", title: "Malware", detail: "Startup items, downloads, apps", isOn: $smartCare.includeMalware)
                ScopeChip(number: "03", title: "Performance", detail: "Memory, CPU, login items, disk", isOn: $smartCare.includePerformance)
            }
            .disabled(smartCare.isScanning)

            Hairline().padding(.top, 28)
            HStack {
                StatusLine(label: "Last scan", value: lastScan)
                Spacer()
                FullDiskAccessStatus()
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 48)
        .padding(.top, 52)
        .padding(.bottom, 24)
    }

    private var caption: String {
        if case .scanning(let progress) = app.smartCare.phase {
            if let finished = app.smartCare.lastFinished {
                return "Checked \(finished.title) · \(progress.completed)/\(progress.total)"
            }
            return "Scanning"
        }
        return app.smartCare.scope.isEmpty ? "Choose something to check" : "A scan only looks"
    }

    private var lastScan: String {
        guard let last = app.smartCare.lastScan else { return "Never" }
        return last.finishedAt.formatted(.relative(presentation: .named))
    }
}

private struct ScanDial: View {
    @Environment(AppModel.self) private var app
    @State private var hovering = false

    var body: some View {
        let smartCare = app.smartCare
        let fraction: Double = if case .scanning(let p) = smartCare.phase { p.fraction } else { 0 }
        ZStack {
            DotRing(progress: fraction, isActive: smartCare.isScanning, diameter: 300, dotCount: 84, dotSize: 4.5)

            if smartCare.isScanning {
                VStack(spacing: 18) {
                    DotMatrixText(text: "\(Int((fraction * 100).rounded()))%", dotSize: 6)
                    Button("Stop") { smartCare.cancel() }
                        .buttonStyle(.pillSmall)
                        .keyboardShortcut(.cancelAction)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Scanning, \(Int((fraction * 100).rounded())) percent")
            } else {
                Button { smartCare.start() } label: {
                    ZStack {
                        Circle()
                            .fill(smartCare.scope.isEmpty ? Theme.tertiary : Theme.primary)
                            .frame(width: 204, height: 204)
                        DotMatrixText(text: "SCAN", dotSize: 4.5, color: Theme.onPrimary)
                    }
                    .scaleEffect(hovering && !smartCare.scope.isEmpty ? 1.02 : 1)
                    .animation(.easeOut(duration: 0.18), value: hovering)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { hovering = $0 }
                .disabled(smartCare.scope.isEmpty)
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel("Scan")
                .accessibilityHint("Checks for junk, threats and performance problems. Nothing is deleted.")
            }
        }
    }
}

private struct ScopeChip: View {
    let number: String
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(alignment: .top, spacing: 12) {
                CheckMark(state: isOn ? .on : .off)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(number).font(Typo.mono(10, .medium)).foregroundStyle(Theme.secondary)
                        Text(title).font(Typo.bodyMedium)
                    }
                    Text(detail).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(isOn ? Theme.surface : Theme.background))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isOn ? .clear : Theme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "included" : "not included")
        .accessibilityAddTraits(.isToggle)
    }
}

// MARK: - Results

private struct SmartCareResultsView: View {
    @Environment(AppModel.self) private var app
    @Environment(NavigationModel.self) private var navigation
    let report: SmartCareReport

    var body: some View {
        let smartCare = app.smartCare
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    ScreenHeader(
                        label: "Scan complete",
                        title: "Here's what we found.",
                        subtitle: "Nothing has been changed yet. Review, then clean up."
                    ) {
                        Button("Scan again") { smartCare.reset() }
                            .buttonStyle(.pill)
                    }

                    VStack(spacing: 0) {
                        Hairline()
                        HStack(alignment: .top, spacing: 0) {
                            junkStat
                            Hairline(vertical: true)
                            securityStat
                            Hairline(vertical: true)
                            performanceStat
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Hairline()
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel("Recommended")
                            .padding(.bottom, 12)
                        if report.recommendations.isEmpty {
                            Text("Nothing to recommend right now.")
                                .font(Typo.body)
                                .foregroundStyle(Theme.secondary)
                                .padding(.vertical, 16)
                        }
                        ForEach(report.recommendations) { recommendation in
                            Hairline()
                            RecommendationRow(recommendation: recommendation)
                        }
                        if !report.recommendations.isEmpty { Hairline() }
                    }

                    if report.security != nil {
                        Text(SecurityReport.disclaimer)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 48)
                .padding(.top, 52)
                .padding(.bottom, 28)
            }

            BottomBar {
                SelectionSummary(
                    bytes: smartCare.selectedFindings.reduce(Int64(0)) { $0 + $1.reclaimableBytes },
                    destination: app.settings.dryRun ? "Dry run" : "Trash"
                )
            } trailing: {
                Button("Review details") { navigation.selection = .cleanup }
                    .buttonStyle(.pill)
                Button(app.settings.dryRun ? "Simulate" : "Clean up") { smartCare.requestClean() }
                    .buttonStyle(.pillPrimary)
                    .disabled(smartCare.selectedFindings.isEmpty || app.cleanup.phase == .cleaning)
            }
        }
    }

    private var junkStat: some View {
        let parts = report.junkBytes.byteParts
        return Stat(
            label: "System junk",
            value: report.scope.contains(.junk) ? parts.value : "-",
            unit: report.scope.contains(.junk) ? parts.unit : "",
            caption: !report.scope.contains(.junk) ? "Not checked"
                : report.inaccessibleCategories.isEmpty
                ? "Reclaimable across \(report.junkCategoryCount) categor\(report.junkCategoryCount == 1 ? "y" : "ies")"
                : "Some folders need Full Disk Access",
            signal: !report.inaccessibleCategories.isEmpty
        )
    }

    private var securityStat: some View {
        let threats = report.threatCount
        let review = (report.security?.findings.count ?? 0) - threats
        return Stat(
            label: "Malware",
            value: report.security == nil ? "-" : "\(threats)",
            unit: report.security == nil ? "" : threats == 1 ? "THREAT" : "THREATS",
            caption: report.security.map { $0.headline + (review > 0 ? " · \(review) to review" : "") } ?? "Not checked",
            signal: threats > 0 || review > 0
        )
    }

    private var performanceStat: some View {
        let count = report.performanceIssueCount
        return Stat(
            label: "Performance",
            value: report.performance == nil ? "-" : "\(count)",
            unit: report.performance == nil ? "" : count == 1 ? "ISSUE" : "ISSUES",
            caption: report.performance == nil ? "Not checked" : count == 0 ? "Running smoothly" : "Startup items, memory, CPU, disk",
            signal: count > 0
        )
    }
}

private struct Stat: View {
    let label: String
    let value: String
    let unit: String
    let caption: String
    var signal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(label, dot: signal ? Theme.accent : nil)
            HStack(alignment: .bottom, spacing: 8) {
                DotMatrixText(text: value, dotSize: 5)
                Text(unit).font(Typo.mono(12, .medium)).tracking(1.2).foregroundStyle(Theme.secondary)
            }
            Text(caption).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(2)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value == "-" ? "not checked" : "\(value) \(unit.lowercased())"). \(caption)")
    }
}

private struct RecommendationRow: View {
    @Environment(AppModel.self) private var app
    let recommendation: Recommendation

    var body: some View {
        let smartCare = app.smartCare
        let isClean = !recommendation.findingIDs.isEmpty
        let remaining = smartCare.remainingBytes(recommendation)
        let done = isClean && remaining == 0

        HStack(spacing: 16) {
            if isClean {
                CheckButton(
                    state: smartCare.selectedRecommendations.contains(recommendation.id) && !done ? .on : .off,
                    label: recommendation.title,
                    isEnabled: !done
                ) { smartCare.toggle(recommendation) }
            } else {
                Circle().fill(Theme.accent).frame(width: 6, height: 6).frame(width: 17).accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(recommendation.title).font(Typo.bodyMedium)
                    .foregroundStyle(done ? Theme.secondary : Theme.primary)
                Text(recommendation.detail)
                    .font(isClean ? Typo.mono(11) : .system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)

            if done {
                Tag(text: "Done")
            } else if isClean {
                if recommendation.includesPermanentDeletion {
                    Tag(text: "Permanent", signal: true)
                        .help("Includes items that can't go to the Trash.")
                }
                Text(remaining.formattedBytes).font(Typo.mono(12, .medium)).frame(minWidth: 70, alignment: .trailing)
                Tag(risk: recommendation.risk)
            } else {
                Tag(risk: recommendation.risk)
                Button(recommendation.action.isReveal ? "Show" : "Open") { smartCare.perform(recommendation.action) }
                    .buttonStyle(.pillSmall)
            }
        }
        .padding(.vertical, 16)
        .accessibilityElement(children: .contain)
    }
}

private extension Recommendation.Action {
    var isReveal: Bool {
        if case .revealInFinder = self { return true }
        return false
    }
}
