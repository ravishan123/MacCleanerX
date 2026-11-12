import Foundation

/// The folders where people keep their own files. Large & old files and
/// duplicates only look (and remove) here.
enum PersonalFolders {
    static let names = ["Documents", "Downloads", "Desktop", "Movies", "Music", "Pictures"]

    static func roots(_ context: ModuleContext) -> [URL] {
        names.map { context.home.appending(path: $0, directoryHint: .isDirectory) }
    }

    /// Libraries managed by apps: never offered as a whole or file by file.
    static let managedLibraries: Set<String> = ["photoslibrary", "musiclibrary", "tvlibrary", "photolibrary", "aplibrary"]

    struct Entry {
        let url: URL
        let size: Int64
        let isPackage: Bool
        let lastUsed: Date?
        let device: Int
        let inode: UInt64
    }

    /// Regular files and bundles (as single entries) under the personal
    /// folders. Hidden files and app-managed libraries are skipped.
    /// Folders full of generated files, never the user's own documents.
    static let generatedFolders: Set<String> = ["node_modules", "DerivedData", ".build", "Pods", "__pycache__"]

    /// `minimumBytes`: smaller regular files are dropped immediately, which
    /// keeps both time and memory low on big folders.
    static func entries(_ context: ModuleContext, minimumBytes: Int64 = 0) throws -> [Entry] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey,
            .contentAccessDateKey, .contentModificationDateKey, .fileResourceIdentifierKey,
        ]
        var result: [Entry] = []
        var sawPermissionError: Error?
        for root in roots(context) {
            do {
                _ = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            } catch {
                if FindingBuilder.isPermissionError(error) { sawPermissionError = error }
                continue
            }
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }
            while let url = enumerator.nextObject() as? URL {
                if Task.isCancelled { return result }
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else { continue }
                if managedLibraries.contains(url.pathExtension.lowercased()) { continue }
                if values.isDirectory == true, values.isPackage != true {
                    if generatedFolders.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                    continue
                }
                let isPackage = values.isPackage == true
                guard values.isRegularFile == true || isPackage else { continue }

                let size: Int64
                if isPackage {
                    size = SizeCalculator.measure(url)?.allocatedBytes ?? 0
                } else {
                    size = Int64(values.totalFileAllocatedSize ?? 0)
                    if size < minimumBytes { continue }
                }
                var st = stat()
                guard lstat(url.path(percentEncoded: false), &st) == 0 else { continue }
                let used = [values.contentAccessDate, values.contentModificationDate].compactMap { $0 }.max()
                result.append(Entry(url: url, size: size, isPackage: isPackage, lastUsed: used,
                                    device: Int(st.st_dev), inode: UInt64(st.st_ino)))
            }
        }
        if result.isEmpty, let sawPermissionError { throw sawPermissionError }
        return result
    }
}

/// Files over a size limit, or unused for a long time, in your personal
/// folders. Everything is Review and nothing is pre-checked.
public struct LargeOldFilesModule: CleanupModule {
    public struct Criteria: Sendable, Hashable {
        public var minimumBytes: Int64
        /// Also include files at least `oldMinimumBytes` big that haven't
        /// been opened for this long. Nil turns the "old" rule off.
        public var unusedFor: TimeInterval?
        public var oldMinimumBytes: Int64

        public init(minimumBytes: Int64 = 50_000_000, unusedFor: TimeInterval? = 365 * 86_400, oldMinimumBytes: Int64 = 1_000_000) {
            self.minimumBytes = minimumBytes
            self.unusedFor = unusedFor
            self.oldMinimumBytes = oldMinimumBytes
        }
    }

    public let category = CleanupCategory.largeOldFiles
    public var criteria: Criteria
    private let support: PathModuleSupport

    public init(context: ModuleContext, criteria: Criteria = Criteria()) {
        self.criteria = criteria
        support = PathModuleSupport(category: category, context: context, roots: PersonalFolders.roots(context))
    }

    public func scan() async -> [Finding] {
        let context = support.context
        let criteria = self.criteria
        let source = ScanSource(root: context.home, risk: .review, accessGroup: "Personal folders") { _ in
            let oldCutoff = criteria.unusedFor.map { context.now().addingTimeInterval(-$0) }
            let floor = criteria.unusedFor == nil ? criteria.minimumBytes : min(criteria.minimumBytes, criteria.oldMinimumBytes)
            return try PersonalFolders.entries(context, minimumBytes: floor)
                .filter { entry in
                    if entry.size >= criteria.minimumBytes { return true }
                    if let oldCutoff, entry.size >= criteria.oldMinimumBytes, let used = entry.lastUsed, used < oldCutoff { return true }
                    return false
                }
                .map { entry in
                    let kind = entry.isPackage
                        ? StorageClassifier.packageCategories[entry.url.pathExtension.lowercased()] ?? .other
                        : StorageClassifier.category(forExtension: entry.url.pathExtension.lowercased())
                    return (url: entry.url, group: kind.displayName)
                }
        }
        return await withLastOpened(support.scan([source]))
    }

    /// Adds the "last opened" date for display.
    private func withLastOpened(_ findings: [Finding]) -> [Finding] {
        findings.map { f in
            guard let url = f.url else { return f }
            let values = try? url.resourceValues(forKeys: [.contentAccessDateKey, .contentModificationDateKey])
            let opened = [values?.contentAccessDate, values?.contentModificationDate].compactMap { $0 }.max()
            return Finding(id: f.id, category: f.category, target: f.target, group: f.group,
                           reclaimableBytes: f.reclaimableBytes, risk: f.risk, skipReason: f.skipReason,
                           scannedIdentity: f.scannedIdentity, lastModified: f.lastModified, lastOpened: opened)
        }
    }

    public func clean(_ findings: [Finding], mode: RemovalMode) async -> CleanResult {
        support.clean(findings, mode: mode)
    }
}
