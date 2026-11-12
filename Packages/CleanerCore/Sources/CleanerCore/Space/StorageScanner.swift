import Foundation
import UniformTypeIdentifiers

/// What kind of data uses space. Used by the storage overview and to group
/// large files.
public enum StorageCategory: String, Sendable, Hashable, CaseIterable {
    case documents, images, videos, audio, archives, apps, developer
    case cachesAndLogs, iosBackups, mail, trash, appData, other

    public var displayName: String {
        switch self {
        case .documents: "Documents"
        case .images: "Images"
        case .videos: "Videos"
        case .audio: "Audio"
        case .archives: "Archives & installers"
        case .apps: "Applications"
        case .developer: "Developer"
        case .cachesAndLogs: "Caches & logs"
        case .iosBackups: "iOS backups"
        case .mail: "Mail"
        case .trash: "Trash"
        case .appData: "App data"
        case .other: "Other files"
        }
    }
}

public struct StorageItem: Sendable, Hashable, Identifiable {
    public let url: URL
    public let bytes: Int64
    public var id: String { url.path }
}

public struct StorageUsage: Sendable, Hashable {
    public var bytes: Int64 = 0
    public var fileCount = 0
    /// Largest files, or folders/bundles for location-based categories.
    public var largest: [StorageItem] = []

    public init() {}
}

public struct StorageReport: Sendable {
    public let volumeTotal: Int64
    public let volumeAvailable: Int64
    public let usage: [StorageCategory: StorageUsage]
    public let unreadableFolders: Int
    public let finishedAt: Date

    public var used: Int64 { max(0, volumeTotal - volumeAvailable) }
    public var measured: Int64 { usage.values.reduce(0) { $0 + $1.bytes } }
    /// macOS, other users, snapshots and anything Mac Cleaner can't read.
    public var systemAndOther: Int64 { max(0, used - measured) }

    public func bytes(_ category: StorageCategory) -> Int64 { usage[category]?.bytes ?? 0 }

    public var sortedCategories: [StorageCategory] {
        StorageCategory.allCases.filter { bytes($0) > 0 }.sorted { bytes($0) > bytes($1) }
    }
}

/// Classifies a path inside the home folder. Pure, so it is unit-tested.
struct StorageClassifier: Sendable {
    let homeComponents: Int

    static let developerFolders: Set<String> = [
        ".npm", ".gradle", ".cargo", ".m2", ".cocoapods", ".rustup", ".pub-cache", "go", ".android", ".nvm", ".pyenv",
    ]
    static let packageCategories: [String: StorageCategory] = [
        "app": .apps, "photoslibrary": .images, "musiclibrary": .audio, "tvlibrary": .videos,
        "imovielibrary": .videos, "fcpbundle": .videos, "logicx": .audio, "band": .audio,
        "xcarchive": .developer, "xcodeproj": .developer, "xcworkspace": .developer,
    ]

    /// Category and the item the bytes are attributed to (file, bundle or top folder).
    func classify(_ path: String) -> (StorageCategory, String) {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let rel = Array(parts.dropFirst(homeComponents))
        func key(_ depth: Int) -> String { "/" + parts.prefix(homeComponents + min(depth, rel.count)).joined(separator: "/") }
        guard let c0 = rel.first else { return (.other, path) }
        let c1 = rel.count > 1 ? rel[1] : "", c2 = rel.count > 2 ? rel[2] : ""

        if c0 == ".Trash" { return (.trash, key(2)) }
        if c0 == "Library" {
            switch c1 {
            case "Caches", "Logs": return (.cachesAndLogs, key(3))
            case "Mail": return (.mail, key(3))
            case "Developer": return (.developer, key(3))
            case "Containers" where c2 == "com.apple.mail": return (.mail, key(3))
            case "Application Support" where c2 == "MobileSync": return (.iosBackups, key(5))
            default: return (.appData, key(3))
            }
        }
        if Self.developerFolders.contains(c0) { return (.developer, key(1)) }

        // Bundles and libraries count as one item.
        for (index, part) in rel.enumerated() {
            let ext = (part as NSString).pathExtension.lowercased()
            if let category = Self.packageCategories[ext], index < rel.count - 1 || ext == "app" {
                return (category, key(index + 1))
            }
            if part == "node_modules" { return (.developer, key(index + 1)) }
        }
        return (Self.category(forExtension: (path as NSString).pathExtension.lowercased()), path)
    }

    private static let typeCache = TypeCache()

    static func category(forExtension ext: String) -> StorageCategory {
        typeCache.value(ext) {
            guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return .other }
            if type.conforms(to: .image) { return .images }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return .videos }
            if type.conforms(to: .audio) { return .audio }
            if type.conforms(to: .archive) || type.conforms(to: .diskImage)
                || type.identifier == "com.apple.installer-package-archive" { return .archives }
            if type.conforms(to: .sourceCode) || type.conforms(to: .script) { return .developer }
            if type.conforms(to: .application) || type.conforms(to: .executable) { return .apps }
            if type.conforms(to: .pdf) || type.conforms(to: .text) || type.conforms(to: .spreadsheet)
                || type.conforms(to: .presentation) || type.conforms(to: .compositeContent) { return .documents }
            return .other
        }
    }

    final class TypeCache: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: StorageCategory] = [:]
        func value(_ key: String, _ make: () -> StorageCategory) -> StorageCategory {
            if let v = lock.withLock({ values[key] }) { return v }
            let v = make()
            lock.withLock { values[key] = v }
            return v
        }
    }
}

/// Measures how space is used in the home folder and the Applications
/// folders. Read-only. Sizes are allocated sizes, so iCloud files that are not
/// downloaded count as zero; APFS clones may be counted more than once, so
/// the overview is an estimate.
public struct StorageScanner: Sendable {
    public var home: URL
    public var applicationFolders: [URL]
    public var largestPerCategory = 60
    /// Files smaller than this only add to totals (keeps memory small).
    public var itemThreshold: Int64 = 1_000_000

    public init(home: URL, applicationFolders: [URL]) {
        self.home = home
        self.applicationFolders = applicationFolders
    }

    public static func live() -> StorageScanner {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return StorageScanner(home: home, applicationFolders: [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appending(path: "Applications", directoryHint: .isDirectory),
        ])
    }

    public func scan(progress: @escaping @Sendable (_ files: Int) -> Void = { _ in }) async -> StorageReport {
        let homePath = SafetyGuard.realpath(home.path(percentEncoded: false)) ?? home.path
        let classifier = StorageClassifier(homeComponents: SafetyGuard.components(homePath).count)
        var usage: [StorageCategory: StorageUsage] = [:]
        var items: [String: (StorageCategory, Int64)] = [:]
        var unreadable = 0
        var files = 0

        func record(_ path: String, bytes: Int64, as classification: (StorageCategory, String)) {
            let (category, key) = classification
            usage[category, default: StorageUsage()].bytes += bytes
            usage[category, default: StorageUsage()].fileCount += 1
            if key != path || bytes >= itemThreshold {
                items[key, default: (category, 0)].1 += bytes
            }
            files += 1
            if files % 5000 == 0 { progress(files) }
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey]
        func walk(_ root: URL, classify: (String) -> (StorageCategory, String)) {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys, options: [],
                errorHandler: { _, _ in unreadable += 1; return true }
            ) else { return }
            while let url = enumerator.nextObject() as? URL {
                if Task.isCancelled { return }
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
                let path = url.path(percentEncoded: false)
                record(path, bytes: Int64(values.totalFileAllocatedSize ?? 0), as: classify(path))
            }
        }

        walk(URL(fileURLWithPath: homePath, isDirectory: true)) { classifier.classify($0) }
        for folder in applicationFolders where !folder.path.hasPrefix(homePath + "/") {
            let apps = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for app in apps where app.pathExtension == "app" {
                let key = app.path(percentEncoded: false)
                walk(app) { _ in (.apps, key) }
            }
        }
        progress(files)

        for (key, value) in items {
            usage[value.0, default: StorageUsage()].largest.append(StorageItem(url: URL(fileURLWithPath: key), bytes: value.1))
        }
        for category in Array(usage.keys) {
            guard var entry = usage[category] else { continue }
            entry.largest = Array(entry.largest.sorted { $0.bytes > $1.bytes }.prefix(largestPerCategory))
            usage[category] = entry
        }

        let volume = try? home.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        return StorageReport(
            volumeTotal: Int64(volume?.volumeTotalCapacity ?? 0),
            volumeAvailable: volume?.volumeAvailableCapacityForImportantUsage ?? 0,
            usage: usage,
            unreadableFolders: unreadable,
            finishedAt: Date()
        )
    }
}
