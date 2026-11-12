import Foundation

/// Unfinished browser downloads in `~/Downloads` (up to three folders deep).
/// Anything still being written is protected by the in-use and 10-minute
/// checks.
public struct BrokenDownloadsModule: CleanupModule {
    public let category = CleanupCategory.brokenDownloads

    /// Extension → browser, for grouping.
    public static let extensions: [String: String] = [
        "crdownload": "Chrome, Edge and Brave",
        "download": "Safari",
        "part": "Firefox",
        "opdownload": "Opera",
    ]
    static let maxDepth = 3

    private let support: PathModuleSupport

    public init(context: ModuleContext) {
        support = PathModuleSupport(category: category, context: context, roots: [context.downloads])
    }

    public func scan() async -> [Finding] {
        let source = ScanSource(root: support.context.downloads, risk: .safe, accessGroup: "Downloads") { root in
            try Self.findPartialDownloads(in: root)
        }
        return await support.scan([source])
    }

    public func clean(_ findings: [Finding], mode: RemovalMode) async -> CleanResult {
        support.clean(findings, mode: mode)
    }

    static func findPartialDownloads(in root: URL) throws -> [ScanSource.Candidate] {
        // Surface permission problems (needs Full Disk Access / Downloads access).
        _ = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)

        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }
        ) else { return [] }

        var results: [ScanSource.Candidate] = []
        while let url = enumerator.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true { continue }
            if let browser = extensions[url.pathExtension.lowercased()] {
                results.append((url: url, group: browser))
                // Safari's .download is a folder bundle: don't look inside.
                if values?.isDirectory == true { enumerator.skipDescendants() }
                continue
            }
            if values?.isDirectory == true, enumerator.level >= maxDepth {
                enumerator.skipDescendants()
            }
        }
        return results
    }
}
