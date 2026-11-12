import Darwin
import Foundation

/// A folder a module looks in, and how to turn its contents into candidates.
struct ScanSource: Sendable {
    typealias Candidate = (url: URL, group: String)

    let root: URL
    let risk: Risk
    /// Group label used for the "needs Full Disk Access" placeholder.
    let accessGroup: String
    /// Lists candidates under `root`. Must be read-only. Throwing a
    /// permission error yields a "needs Full Disk Access" placeholder.
    let list: @Sendable (URL) throws -> [Candidate]

    /// Every top-level entry of `root`, minus `.DS_Store` and anything for
    /// which `include` returns false.
    static func topLevel(
        _ root: URL,
        risk: Risk,
        accessGroup: String,
        include: @escaping @Sendable (URL) -> Bool = { _ in true },
        group: @escaping @Sendable (URL) -> String
    ) -> ScanSource {
        ScanSource(root: root, risk: risk, accessGroup: accessGroup) { root in
            try FileManager.default
                .contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [])
                .filter { $0.lastPathComponent != ".DS_Store" && include($0) }
                .map { (url: $0, group: group($0)) }
        }
    }
}

/// Shared scan/clean behaviour for modules that remove files.
struct PathModuleSupport: Sendable {
    let category: CleanupCategory
    let context: ModuleContext
    let safetyGuard: SafetyGuard

    init(category: CleanupCategory, context: ModuleContext, roots: [URL]) {
        self.category = category
        self.context = context
        self.safetyGuard = SafetyGuard(allowedRoots: roots, home: context.home)
    }

    func scan(_ sources: [ScanSource]) async -> [Finding] {
        let openFiles = context.openFiles()
        var all: [Finding] = []
        for source in sources {
            let builder = FindingBuilder(
                category: category, risk: source.risk, safetyGuard: safetyGuard,
                context: context, openFiles: openFiles
            )
            do {
                let candidates = try source.list(source.root)
                all += await builder.makeAll(candidates)
            } catch {
                if FindingBuilder.isPermissionError(error) {
                    all.append(builder.needsAccess(source.root, group: source.accessGroup))
                }
                // Missing folders simply have nothing to clean.
            }
        }
        return all.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    /// Rejects findings from other categories and permanent-only items when
    /// the mode is Move to Trash, then removes the rest through `Remover`.
    func clean(_ findings: [Finding], mode: RemovalMode) -> CleanResult {
        var result = CleanResult(mode: mode)
        var accepted: [Finding] = []
        for finding in findings {
            if finding.category != category {
                result.failed.append(.init(findingID: finding.id, target: finding.target, reason: "Belongs to another category"))
            } else if case .command = finding.target {
                result.failed.append(.init(findingID: finding.id, target: finding.target, reason: "Not a file item"))
            } else {
                accepted.append(finding)
            }
        }
        let removed = Remover(safetyGuard: safetyGuard, context: context).remove(accepted, mode: mode)
        result.removed += removed.removed
        result.failed += removed.failed
        return result
    }

    static func isRegularOrDirectory(_ url: URL) -> Bool {
        var st = stat()
        guard lstat(url.path(percentEncoded: false), &st) == 0 else { return false }
        let type = st.st_mode & S_IFMT
        return type == S_IFREG || type == S_IFDIR
    }
}
