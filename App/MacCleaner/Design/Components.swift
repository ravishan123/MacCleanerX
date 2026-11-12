import CleanerCore
import SwiftUI

// MARK: - Formatting

extension Int64 {
    var formattedBytes: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }

    /// "12.4" and "GB", for showing the number and unit separately.
    var byteParts: (value: String, unit: String) {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        formatter.includesUnit = false
        let value = formatter.string(fromByteCount: self)
        formatter.includesUnit = true
        formatter.includesCount = false
        return (value, formatter.string(fromByteCount: self).uppercased())
    }
}

extension CleanupCategory {
    var symbol: String {
        switch self {
        case .systemCache: "internaldrive"
        case .applicationLogs: "doc.text"
        case .temporaryFiles: "clock.arrow.circlepath"
        case .brokenDownloads: "arrow.down.circle"
        case .mailAttachments: "paperclip"
        case .trash: "trash"
        case .xcodeJunk: "hammer"
        case .developerCaches: "shippingbox"
        case .iosUpdates, .iosBackups: "iphone"
        case .installers: "opticaldiscdrive"
        case .brokenStartupItems: "bolt.slash"
        case .largeOldFiles: "doc.badge.clock"
        case .duplicates: "square.on.square"
        case .applications: "app"
        case .appLeftovers: "archivebox"
        }
    }

    var footnote: String {
        switch self {
        case .systemCache:
            "Apps rebuild their cache the next time they open. Items in use or changed in the last 10 minutes are skipped."
        case .applicationLogs:
            "Logs and crash reports help with troubleshooting. Removing them doesn't change how your apps work."
        case .temporaryFiles:
            "Files apps left in your temporary folder. Anything open or recently changed is skipped."
        case .brokenDownloads:
            "Unfinished browser downloads. Downloads still in progress are skipped."
        case .mailAttachments:
            "Copies Mail saved when you opened attachments. The originals stay in your mailbox."
        case .trash:
            "Emptying the Trash permanently deletes these items. This can't be undone."
        case .xcodeJunk:
            "Build files, device support and simulator caches are rebuilt automatically. Archives are needed to read crash reports from shipped builds."
        case .developerCaches:
            "Package caches for npm, Gradle, Cargo, Go, Dart and CocoaPods are downloaded again when needed. The Maven repository can hold your own builds, so review it."
        case .iosUpdates:
            "iPhone and iPad software Finder downloaded. It's downloaded again if you need it."
        case .iosBackups:
            "Backups of your iPhone or iPad. A backup may be the only copy of a device's data, so make sure you no longer need it."
        case .installers:
            "Disk images and installer packages in Downloads older than a week. Usually the app is already installed."
        case .brokenStartupItems:
            "Startup items whose program has been deleted. They fail every time you log in."
        case .largeOldFiles:
            "Big files and files you haven't opened for a long time. Only you know if you still need them."
        case .duplicates:
            "Exact copies, confirmed byte for byte. At least one copy always stays."
        case .applications:
            "Apps go to the Trash, so you can put them back."
        case .appLeftovers:
            "Files named after apps that are no longer installed."
        }
    }
}

// MARK: - Type and structure

/// Small uppercase monospaced label, optionally with a signal dot.
struct SectionLabel: View {
    let text: String
    var dot: Color?

    init(_ text: String, dot: Color? = nil) {
        self.text = text
        self.dot = dot
    }

    var body: some View {
        HStack(spacing: 7) {
            if let dot {
                Circle().fill(dot).frame(width: 6, height: 6).accessibilityHidden(true)
            }
            Text(text.uppercased())
                .font(Typo.mono(11, .medium))
                .tracking(1.6)
                .foregroundStyle(Theme.secondary)
        }
    }
}

struct ScreenHeader<Trailing: View>: View {
    let label: String
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(label, dot: Theme.accent)
                Text(title)
                    .font(Typo.title)
                    .foregroundStyle(Theme.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(Typo.body)
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 16)
            trailing
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(label: String, title: String, subtitle: String) {
        self.init(label: label, title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct Hairline: View {
    var vertical = false
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
            .accessibilityHidden(true)
    }
}

struct BottomBar<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 14) {
                leading
                Spacer(minLength: 12)
                trailing
            }
            .padding(.horizontal, 40)
            .frame(height: 68)
        }
        .background(Theme.background)
    }
}

/// "SELECTED  12.4 GB  → TRASH"
struct SelectionSummary: View {
    let bytes: Int64
    let destination: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("SELECTED").font(Typo.mono(10, .medium)).tracking(1.4).foregroundStyle(Theme.secondary)
            Text(bytes.formattedBytes).font(Typo.mono(14, .semibold)).foregroundStyle(Theme.primary)
            Text("→ " + destination.uppercased()).font(Typo.mono(10, .medium)).tracking(1.2).foregroundStyle(Theme.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Selected \(bytes.formattedBytes), \(destination)")
    }
}

// MARK: - Buttons

struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive, quiet }
    var kind: Kind
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 12 : 13, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, compact ? 12 : 18)
            .frame(height: compact ? 26 : 34)
            .foregroundStyle(foreground)
            .background(Capsule().fill(background))
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.35)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: Theme.onPrimary
        case .destructive: .white
        case .secondary, .quiet: Theme.primary
        }
    }

    private var background: Color {
        switch kind {
        case .primary: Theme.primary
        case .destructive: Theme.accent
        case .secondary: Theme.background
        case .quiet: Theme.surface
        }
    }

    private var border: Color {
        switch kind {
        case .secondary: Theme.primary.opacity(0.85)
        default: .clear
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pillPrimary: PillButtonStyle { PillButtonStyle(kind: .primary) }
    static var pill: PillButtonStyle { PillButtonStyle(kind: .secondary) }
    static var pillDestructive: PillButtonStyle { PillButtonStyle(kind: .destructive) }
    static var pillSmall: PillButtonStyle { PillButtonStyle(kind: .secondary, compact: true) }
    static var pillQuiet: PillButtonStyle { PillButtonStyle(kind: .quiet, compact: true) }
}

// MARK: - Checkboxes

struct CheckMark: View {
    let state: TriState
    var isEnabled = true

    var body: some View {
        ZStack {
            if state == .off {
                Circle().strokeBorder(isEnabled ? Theme.secondary : Theme.tertiary, lineWidth: 1.2)
            } else {
                Circle().fill(Theme.primary)
                Image(systemName: state == .on ? "checkmark" : "minus")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Theme.onPrimary)
            }
        }
        .frame(width: 17, height: 17)
        .opacity(isEnabled ? 1 : 0.45)
        .contentShape(Circle())
    }
}

struct CheckButton: View {
    let state: TriState
    let label: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) { CheckMark(state: state, isEnabled: isEnabled) }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityLabel(label)
            .accessibilityValue(state == .on ? "checked" : state == .mixed ? "partly checked" : "unchecked")
            .accessibilityAddTraits(.isToggle)
    }
}

struct CheckToggle: View {
    @Binding var isOn: Bool
    let label: String
    var isEnabled = true

    var body: some View {
        CheckButton(state: isOn ? .on : .off, label: label, isEnabled: isEnabled) { isOn.toggle() }
    }
}

// MARK: - Tags and status

struct Tag: View {
    let text: String
    var signal = false

    var body: some View {
        HStack(spacing: 5) {
            if signal {
                Circle().fill(Theme.accent).frame(width: 5, height: 5).accessibilityHidden(true)
            }
            Text(text.uppercased())
                .font(Typo.mono(9.5, .semibold))
                .tracking(1.1)
        }
        .foregroundStyle(Theme.primary)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .overlay(Capsule().strokeBorder(Theme.tertiary, lineWidth: 1))
        .fixedSize()
    }
}

extension Tag {
    init(risk: Risk) {
        self.init(text: risk == .safe ? "Safe" : "Review", signal: risk == .review)
    }

    init(skip reason: SkipReason) {
        switch reason {
        case .inUse: self.init(text: "In use")
        case .recentlyModified: self.init(text: "Recent")
        case .needsFullDiskAccess: self.init(text: "No access", signal: true)
        }
    }
}

extension SkipReason {
    var explanation: String {
        switch self {
        case .inUse: "An open app is using this item, so it's skipped."
        case .recentlyModified: "Changed in the last 10 minutes, so it's skipped."
        case .needsFullDiskAccess: "Mac Cleaner needs Full Disk Access to read this folder."
        }
    }
}

/// "● FULL DISK ACCESS  GRANTED"
struct StatusLine: View {
    let label: String
    let value: String
    var signal = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(signal ? Theme.accent : Theme.primary)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(label.uppercased()).font(Typo.mono(10, .medium)).tracking(1.4).foregroundStyle(Theme.secondary)
            Text(value.uppercased()).font(Typo.mono(10, .semibold)).tracking(1.4).foregroundStyle(Theme.primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

struct FullDiskAccessStatus: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if app.settings.fullDiskAccess == .granted {
            StatusLine(label: "Full Disk Access", value: "Granted")
        } else {
            Button { app.showOnboarding = true } label: {
                StatusLine(label: "Full Disk Access", value: "Not granted", signal: true)
            }
            .buttonStyle(.plain)
            .help("Some folders can't be checked without Full Disk Access.")
        }
    }
}
