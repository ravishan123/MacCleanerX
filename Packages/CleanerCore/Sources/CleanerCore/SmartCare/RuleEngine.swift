import Foundation

/// A suggested next step on the Smart Care results screen.
public struct Recommendation: Sendable, Hashable, Identifiable {
    public enum Action: Sendable, Hashable {
        /// Clean these findings (after the usual confirmation).
        case clean([UUID])
        case openLoginItemsSettings
        case openActivityMonitor
        case openStorageSettings
        case revealInFinder(URL)
    }

    public let id: String
    public let title: String
    public let detail: String
    public let bytes: Int64?
    public let risk: Risk
    public let action: Action
    /// Some or all items can't go to the Trash (extra confirmation needed).
    public let includesPermanentDeletion: Bool

    /// Only Safe cleanups are pre-selected.
    public var isSelectedByDefault: Bool {
        if case .clean = action { return risk == .safe }
        return false
    }

    public var findingIDs: [UUID] {
        if case .clean(let ids) = action { return ids }
        return []
    }
}

/// Maps scan results to recommendations with a Safe/Review label.
public enum RuleEngine {

    struct CleanRule: Sendable {
        let id: String
        let title: String
        let detail: String
        let risk: Risk
        let matches: @Sendable (Finding) -> Bool
    }

    static let cleanRules: [CleanRule] = [
        CleanRule(id: "cache-logs", title: "Remove system cache and application logs",
                  detail: "~/Library/Caches · ~/Library/Logs", risk: .safe) {
            ($0.category == .systemCache || $0.category == .applicationLogs) && $0.risk == .safe
        },
        CleanRule(id: "xcode", title: "Remove Xcode build files and unavailable simulators",
                  detail: "~/Library/Developer", risk: .safe) {
            $0.category == .xcodeJunk && $0.risk == .safe
        },
        CleanRule(id: "dev-caches", title: "Remove developer caches and iOS update files",
                  detail: "~/.npm · ~/.gradle · ~/.cargo · ~/Library/iTunes", risk: .safe) {
            ($0.category == .developerCaches || $0.category == .iosUpdates) && $0.risk == .safe
        },
        CleanRule(id: "temp-downloads", title: "Remove temporary files and broken downloads",
                  detail: "$TMPDIR · ~/Downloads/*.crdownload, *.part, *.download", risk: .safe) {
            $0.category == .temporaryFiles || $0.category == .brokenDownloads
        },
        CleanRule(id: "trash", title: "Empty the Trash",
                  detail: "~/.Trash · this can't be undone", risk: .review) {
            $0.category == .trash
        },
        CleanRule(id: "mail", title: "Review Mail attachments",
                  detail: "Copies Mail saved when you opened attachments", risk: .review) {
            $0.category == .mailAttachments
        },
        CleanRule(id: "installers", title: "Review old installers in Downloads",
                  detail: "~/Downloads/*.dmg, *.pkg older than a week", risk: .review) {
            $0.category == .installers
        },
        CleanRule(id: "ios-backups", title: "Review iPhone and iPad backups",
                  detail: "~/Library/Application Support/MobileSync/Backup", risk: .review) {
            $0.category == .iosBackups
        },
        CleanRule(id: "startup", title: "Remove broken startup items",
                  detail: "~/Library/LaunchAgents · their programs are gone", risk: .review) {
            $0.category == .brokenStartupItems
        },
        CleanRule(id: "maven", title: "Review the Maven repository",
                  detail: "~/.m2/repository", risk: .review) {
            $0.category == .developerCaches && $0.risk == .review
        },
        CleanRule(id: "archives", title: "Review old Xcode archives",
                  detail: "~/Library/Developer/Xcode/Archives", risk: .review) {
            $0.category == .xcodeJunk && $0.risk == .review
        },
    ]

    public static func recommendations(
        junk: [CleanupCategory: [Finding]],
        security: SecurityReport?,
        performance: PerformanceReport?
    ) -> [Recommendation] {
        var result: [Recommendation] = []
        let cleanable = CleanupCategory.allCases.flatMap { junk[$0] ?? [] }.filter { $0.skipReason == nil }

        for rule in cleanRules {
            let items = cleanable.filter(rule.matches)
            let bytes = items.reduce(Int64(0)) { $0 + $1.reclaimableBytes }
            guard !items.isEmpty, bytes > 0 else { continue }
            result.append(Recommendation(
                id: rule.id, title: rule.title, detail: rule.detail, bytes: bytes, risk: rule.risk,
                action: .clean(items.map(\.id)),
                includesPermanentDeletion: items.contains(where: \.requiresPermanentDeletion)
            ))
        }

        for finding in security?.findings ?? [] {
            result.append(Recommendation(
                id: "security-\(finding.id)",
                title: finding.severity == .suspicious ? "Check “\(finding.title)”" : "Review “\(finding.title)”",
                detail: finding.reasons.first ?? finding.path.path,
                bytes: nil, risk: .review, action: .revealInFinder(finding.path),
                includesPermanentDeletion: false
            ))
        }

        for issue in performance?.issues ?? [] {
            let action: Recommendation.Action = switch issue.kind {
            case .startupItems: .openLoginItemsSettings
            case .memoryPressure, .cpuHog: .openActivityMonitor
            case .lowDiskSpace: .openStorageSettings
            }
            let title = issue.kind == .startupItems ? "Review login items that slow startup" : issue.title
            result.append(Recommendation(
                id: "perf-\(issue.id)", title: title, detail: issue.detail, bytes: nil,
                risk: .review, action: action, includesPermanentDeletion: false
            ))
        }
        return result
    }
}
