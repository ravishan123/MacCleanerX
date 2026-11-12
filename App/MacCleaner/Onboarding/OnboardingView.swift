import CleanerCore
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let granted = app.settings.fullDiskAccess == .granted
        VStack(alignment: .leading, spacing: 0) {
            DotMatrixText(text: "HELLO", dotSize: 6)
                .padding(.bottom, 24)
            Text("A cleaner Mac, on your terms.")
                .font(Typo.title)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 28)

            VStack(alignment: .leading, spacing: 0) {
                point("01", "Scans only look. Nothing is removed until you review the list and confirm.")
                point("02", "Items go to the Trash by default, so you can put them back.")
                point("03", "Only your own files are touched. System files are always off-limits.")
            }

            HStack {
                SectionLabel("Full Disk Access", dot: granted ? nil : Theme.accent)
                Spacer()
                FullDiskAccessStatus()
            }
            .padding(.top, 32)
            .padding(.bottom, 12)

            if granted {
                Text("Mac Cleaner can check every folder it supports.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            } else {
                Text("Without it, macOS hides the Trash, Mail attachments and some caches. Those show “no access”. Everything else still works.")
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 12)
                VStack(alignment: .leading, spacing: 6) {
                    step("A", "Click Open System Settings.")
                    step("B", "Under Privacy & Security › Full Disk Access, turn on Mac Cleaner. Not listed? Click + and choose it in Applications.")
                    step("C", "Quit and reopen Mac Cleaner.")
                }
            }

            HStack(spacing: 10) {
                if !granted {
                    Button("Open System Settings") { app.settings.openFullDiskAccessSettings() }
                        .buttonStyle(.pill)
                    Button("Check again") { app.settings.refreshFullDiskAccess() }
                        .buttonStyle(.pill)
                }
                Spacer()
                Button(granted ? "Get started" : "Continue without access") { app.finishOnboarding() }
                    .buttonStyle(.pillPrimary)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 32)
        }
        .padding(40)
        .frame(width: 580)
        .background(Theme.background)
    }

    private func point(_ number: String, _ text: String) -> some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(number).font(Typo.mono(10, .medium)).foregroundStyle(Theme.secondary)
                Text(text).font(Typo.body).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12)
        }
        .accessibilityElement(children: .combine)
    }

    private func step(_ letter: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(letter).font(Typo.mono(10, .semibold)).foregroundStyle(Theme.secondary)
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
