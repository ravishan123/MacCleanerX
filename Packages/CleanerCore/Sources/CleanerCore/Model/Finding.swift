import Foundation

/// How confident we are that removing a finding is harmless.
public enum Risk: String, Sendable, Codable, Hashable {
    /// Regenerated automatically (caches, logs, build products).
    case safe
    /// The user should look before removing (Trash, attachments, archives).
    case review
}

/// The cleanup categories shown in the Cleanup sidebar.
public enum CleanupCategory: String, Sendable, Codable, Hashable, CaseIterable {
    // Junk categories (Cleanup screen and Smart Care)
    case systemCache
    case applicationLogs
    case temporaryFiles
    case brokenDownloads
    case mailAttachments
    case trash
    case xcodeJunk
    case developerCaches
    case iosUpdates
    case iosBackups
    case installers
    case brokenStartupItems
    // Tools (their own screens)
    case largeOldFiles
    case duplicates
    case applications
    case appLeftovers

    public var displayName: String {
        switch self {
        case .systemCache: "System cache"
        case .applicationLogs: "Application logs"
        case .temporaryFiles: "Temporary files"
        case .brokenDownloads: "Broken downloads"
        case .mailAttachments: "Mail attachments"
        case .trash: "Trash bins"
        case .xcodeJunk: "Xcode junk"
        case .developerCaches: "Developer caches"
        case .iosUpdates: "iOS update files"
        case .iosBackups: "iOS device backups"
        case .installers: "Old installers"
        case .brokenStartupItems: "Broken startup items"
        case .largeOldFiles: "Large & old files"
        case .duplicates: "Duplicates"
        case .applications: "Applications"
        case .appLeftovers: "Leftovers of deleted apps"
        }
    }

    /// Categories shown on the Cleanup screen and checked by Smart Care.
    public static let junkCases: [CleanupCategory] = [
        .systemCache, .applicationLogs, .temporaryFiles, .brokenDownloads, .mailAttachments,
        .trash, .xcodeJunk, .developerCaches, .iosUpdates, .iosBackups, .installers, .brokenStartupItems,
    ]

    public var isJunk: Bool { Self.junkCases.contains(self) }
}

/// Why a finding is shown but left unchecked.
public enum SkipReason: String, Sendable, Codable, Hashable {
    case inUse
    case recentlyModified
    case needsFullDiskAccess
}

/// Non-path actions that a module can perform (they cannot go through
/// `SafetyGuard`, so each one gets its own preview and confirmation).
public enum CommandAction: String, Sendable, Codable, Hashable {
    /// `xcrun simctl delete unavailable`
    case deleteUnavailableSimulators
}

/// What a finding refers to.
public enum FindingTarget: Sendable, Hashable {
    case path(URL)
    case command(CommandAction)
}

/// One removable item discovered by a scan. Scanning only produces findings;
/// it never changes anything on disk.
public struct Finding: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let category: CleanupCategory
    public let target: FindingTarget
    /// Display group, e.g. the app that owns a cache folder.
    public let group: String
    /// Bytes that removal would actually free (hard links and clone-shared
    /// blocks are not counted).
    public let reclaimableBytes: Int64
    public let risk: Risk
    /// Non-nil means the item is shown but unchecked by default.
    public let skipReason: SkipReason?
    /// Identity captured by `SafetyGuard` at scan time, so removal can detect
    /// an item that was swapped after the scan.
    public let scannedIdentity: SafetyGuard.ValidatedPath?
    /// Newest modification inside the item.
    public let lastModified: Date?
    /// Last time the file was opened, when known.
    public let lastOpened: Date?
    /// Content hash shared by every copy in a duplicate set.
    public let duplicateSet: String?
    /// Other copies in the same duplicate set.
    public let relatedPaths: [URL]

    public init(
        id: UUID = UUID(),
        category: CleanupCategory,
        target: FindingTarget,
        group: String,
        reclaimableBytes: Int64,
        risk: Risk,
        skipReason: SkipReason? = nil,
        scannedIdentity: SafetyGuard.ValidatedPath? = nil,
        lastModified: Date? = nil,
        lastOpened: Date? = nil,
        duplicateSet: String? = nil,
        relatedPaths: [URL] = []
    ) {
        self.id = id
        self.category = category
        self.target = target
        self.group = group
        self.reclaimableBytes = reclaimableBytes
        self.risk = risk
        self.skipReason = skipReason
        self.scannedIdentity = scannedIdentity
        self.lastModified = lastModified
        self.lastOpened = lastOpened
        self.duplicateSet = duplicateSet
        self.relatedPaths = relatedPaths
    }

    /// Safe items are pre-checked; Review items and skipped items are not.
    public var isSelectedByDefault: Bool { skipReason == nil && risk == .safe }

    /// True for items that cannot go to the Trash (they are already there,
    /// or the removal is a command such as `simctl delete`). The UI must get
    /// the extra permanent-deletion confirmation for these.
    public var requiresPermanentDeletion: Bool {
        if category == .trash { return true }
        if case .command = target { return true }
        return false
    }

    /// The path for display (or a description for command actions).
    public var displayPath: String {
        switch target {
        case .path(let url): url.path(percentEncoded: false)
        case .command(.deleteUnavailableSimulators): "xcrun simctl delete unavailable"
        }
    }

    public var displayName: String {
        switch target {
        case .path(let url): url.lastPathComponent
        case .command(.deleteUnavailableSimulators): "Unavailable simulators"
        }
    }

    public var url: URL? {
        if case .path(let url) = target { return url }
        return nil
    }
}
