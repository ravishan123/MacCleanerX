import CryptoKit
import Foundation

/// Exact duplicate files in your personal folders.
///
/// Files are grouped by size, then by a hash of their first and last 64 KB,
/// then confirmed with a full SHA-256. Hard links to the same file are not
/// duplicates. APFS clones are reported, but their reclaimable size is 0
/// because removing one frees nothing.
///
/// Safety: `clean` only removes copies from a set when another copy that is
/// not being removed still exists and still has the same SHA-256.
public struct DuplicatesModule: CleanupModule {
    public let category = CleanupCategory.duplicates
    public var minimumBytes: Int64
    private let support: PathModuleSupport

    public init(context: ModuleContext, minimumBytes: Int64 = 1_000_000) {
        self.minimumBytes = minimumBytes
        support = PathModuleSupport(category: category, context: context, roots: PersonalFolders.roots(context))
    }

    public func scan() async -> [Finding] {
        let context = support.context
        let minimum = minimumBytes
        guard let entries = try? PersonalFolders.entries(context) else {
            return await support.scan([ScanSource(root: context.home, risk: .review, accessGroup: "Personal folders") { _ in
                _ = try PersonalFolders.entries(context)
                return []
            }])
        }
        let sets = Self.duplicateSets(entries.filter { !$0.isPackage && $0.size >= minimum })

        let builder = FindingBuilder(category: category, risk: .review, safetyGuard: support.safetyGuard,
                                     context: context, openFiles: context.openFiles())
        var findings: [Finding] = []
        for (hash, urls) in sets {
            for url in urls {
                if let finding = builder.make(url, group: urls[0].lastPathComponent, duplicateSet: hash,
                                              relatedPaths: urls.filter { $0 != url }) {
                    findings.append(finding)
                }
            }
        }
        return findings.sorted {
            ($0.reclaimableBytes, $0.duplicateSet ?? "", $0.displayPath) > ($1.reclaimableBytes, $1.duplicateSet ?? "", $1.displayPath)
        }
    }

    public func clean(_ findings: [Finding], mode: RemovalMode) async -> CleanResult {
        var result = CleanResult(mode: mode)
        var accepted: [Finding] = []
        for (set, members) in Dictionary(grouping: findings, by: { $0.duplicateSet ?? "" }) {
            if set.isEmpty || !Self.anotherCopyRemains(set: set, removing: members) {
                result.failed += members.map {
                    .init(findingID: $0.id, target: $0.target, reason: "No other identical copy would remain")
                }
            } else {
                accepted += members
            }
        }
        let removed = support.clean(accepted, mode: mode)
        result.removed += removed.removed
        result.failed += removed.failed
        return result
    }

    // MARK: Matching

    static func duplicateSets(_ entries: [PersonalFolders.Entry]) -> [(String, [URL])] {
        var result: [(String, [URL])] = []
        for (_, sameSize) in Dictionary(grouping: entries, by: \.size) where sameSize.count > 1 {
            // Hard links are the same file, not copies.
            var seen = Set<String>()
            let distinct = sameSize.filter { seen.insert("\($0.device):\($0.inode)").inserted }
            guard distinct.count > 1 else { continue }

            for (_, samePartial) in Dictionary(grouping: distinct, by: { partialHash($0.url) ?? UUID().uuidString })
            where samePartial.count > 1 {
                for (full, sameFull) in Dictionary(grouping: samePartial, by: { fullHash($0.url) ?? UUID().uuidString })
                where sameFull.count > 1 {
                    if Task.isCancelled { return result }
                    result.append((full, sameFull.map(\.url).sorted { $0.path < $1.path }))
                }
            }
        }
        return result
    }

    static func anotherCopyRemains(set: String, removing members: [Finding]) -> Bool {
        func canonical(_ url: URL) -> String {
            SafetyGuard.realpath(url.path(percentEncoded: false)) ?? url.standardizedFileURL.path
        }
        let removing = Set(members.compactMap { $0.url.map(canonical) })
        let peers = Set(members.flatMap(\.relatedPaths).map(canonical)).subtracting(removing)
        return peers.contains { path in
            var st = stat()
            guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return false }
            return fullHash(URL(fileURLWithPath: path)) == set
        }
    }

    static let chunk = 64 * 1024

    static func partialHash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        guard let head = try? handle.read(upToCount: chunk) else { return nil }
        hasher.update(data: head)
        if let end = try? handle.seekToEnd(), end > UInt64(chunk * 2) {
            try? handle.seek(toOffset: end - UInt64(chunk))
            if let tail = try? handle.read(upToCount: chunk) { hasher.update(data: tail) }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func fullHash(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            if Task.isCancelled { return nil }
            let data: Data
            do {
                // `read(upToCount:)` returns nil at end of file.
                data = try handle.read(upToCount: 1 << 20) ?? Data()
            } catch {
                return nil
            }
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
