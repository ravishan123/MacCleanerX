import CleanerCore
import SwiftUI

/// The only way a cleanup can start. Step 1 states exactly how many items
/// and how much space; step 2 (only when something will be permanently
/// deleted) asks again, with Cancel as the default button.
struct CleanConfirmation: ViewModifier {
    @Binding var plan: CleanPlan?
    let perform: (CleanPlan) -> Void
    @State private var secondStep: CleanPlan?

    func body(content: Content) -> some View {
        content
            .alert(
                plan.map(Self.title) ?? "",
                isPresented: Binding(get: { plan != nil }, set: { if !$0 { plan = nil } }),
                presenting: plan
            ) { plan in
                if plan.needsSecondConfirmation {
                    Button("Continue…") {
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(200))
                            secondStep = plan
                        }
                    }
                } else {
                    Button(plan.dryRun ? "Simulate" : "Move to Trash") { perform(plan) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { plan in
                Text(Self.message(plan))
            }
            .alert(
                "This can't be undone",
                isPresented: Binding(get: { secondStep != nil }, set: { if !$0 { secondStep = nil } }),
                presenting: secondStep
            ) { plan in
                Button("Delete Permanently", role: .destructive) { perform(plan) }
                Button("Cancel", role: .cancel) {}
                    .keyboardShortcut(.defaultAction)
            } message: { plan in
                let items = plan.permanentItems
                let bytes = items.reduce(Int64(0)) { $0 + $1.reclaimableBytes }
                Text("\(Self.count(items.count)) (\(bytes.formattedBytes)) will be permanently deleted. They won't go to the Trash and can't be recovered.")
            }
    }

    static func count(_ n: Int) -> String { n == 1 ? "1 item" : "\(n) items" }

    static func title(_ plan: CleanPlan) -> String {
        if plan.dryRun { return "Simulate removing \(count(plan.count))?" }
        if plan.permanentToggle { return "Permanently delete \(count(plan.count))?" }
        if plan.regular.isEmpty { return "Permanently delete \(count(plan.count))?" }
        if !plan.permanentOnly.isEmpty { return "Clean up \(count(plan.count))?" }
        return "Move \(count(plan.count)) to the Trash?"
    }

    static func message(_ plan: CleanPlan) -> String {
        var parts = ["This frees about \(plan.bytes.formattedBytes)."]
        if plan.dryRun {
            parts.append("Dry-run mode is on, so nothing will be changed. The activity log will show what would have been removed.")
            return parts.joined(separator: " ")
        }
        let trash = plan.trashItems
        if !trash.isEmpty {
            parts.append("\(count(trash.count)) (\(trash.reduce(Int64(0)) { $0 + $1.reclaimableBytes }.formattedBytes)) will go to the Trash, so you can put them back.")
        }
        if !plan.permanentOnly.isEmpty, !plan.permanentToggle {
            let bytes = plan.permanentOnly.reduce(Int64(0)) { $0 + $1.reclaimableBytes }
            parts.append("\(count(plan.permanentOnly.count)) (\(bytes.formattedBytes)) can't go to the Trash (items already in the Trash, or unavailable simulators) and will be deleted permanently.")
        }
        if plan.permanentToggle {
            parts.append("“Delete permanently” is on, so nothing goes to the Trash.")
        }
        return parts.joined(separator: " ")
    }
}

extension View {
    func cleanConfirmation(plan: Binding<CleanPlan?>, perform: @escaping (CleanPlan) -> Void) -> some View {
        modifier(CleanConfirmation(plan: plan, perform: perform))
    }
}

/// Summary shown after a cleanup or dry run.
struct CleanOutcomeSheet: View {
    let outcome: CleanOutcome
    let showActivity: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let result = outcome.result
        let parts = result.bytesFreed.byteParts
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(outcome.dryRun ? "Dry run" : result.removed.isEmpty ? "Nothing removed" : "Done",
                         dot: result.failed.isEmpty ? nil : Theme.accent)
                .padding(.bottom, 20)
            HStack(alignment: .bottom, spacing: 10) {
                DotMatrixText(text: parts.value, dotSize: 7)
                Text(parts.unit).font(Typo.mono(13, .medium)).foregroundStyle(Theme.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(headline)
            Text(headline).font(.system(size: 18, weight: .light)).padding(.top, 16)
            Text(subheadline).font(.system(size: 12)).foregroundStyle(Theme.secondary).padding(.top, 4)

            if !result.failed.isEmpty {
                SectionLabel("\(CleanConfirmation.count(result.failed.count)) skipped", dot: Theme.accent)
                    .padding(.top, 28)
                    .padding(.bottom, 8)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(result.failed, id: \.findingID) { failure in
                            Hairline()
                            VStack(alignment: .leading, spacing: 3) {
                                Text(outcome.findings[failure.findingID]?.displayName ?? "Item").font(Typo.body)
                                Text(failure.reason).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                            }
                            .padding(.vertical, 9)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            HStack {
                Button("Activity log") {
                    dismiss()
                    showActivity()
                }
                .buttonStyle(.pill)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.pillPrimary)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 32)
        }
        .padding(36)
        .frame(width: 480)
        .background(Theme.background)
    }

    private var headline: String {
        let r = outcome.result
        if outcome.dryRun { return "\(r.bytesFreed.formattedBytes) would be freed" }
        if r.removed.isEmpty { return "Nothing was removed" }
        return "\(r.bytesFreed.formattedBytes) freed"
    }

    private var subheadline: String {
        let r = outcome.result
        if outcome.dryRun { return "\(CleanConfirmation.count(r.removed.count)) would be removed. Nothing was changed." }
        let trashed = r.removed.filter { $0.trashedURL != nil }.count
        let deleted = r.removed.count - trashed
        var parts: [String] = []
        if trashed > 0 { parts.append("\(CleanConfirmation.count(trashed)) moved to the Trash") }
        if deleted > 0 { parts.append("\(CleanConfirmation.count(deleted)) deleted permanently") }
        return parts.isEmpty ? "Every selected item was skipped." : parts.joined(separator: " · ")
    }
}
