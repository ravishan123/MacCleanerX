import Foundation

/// Shared, read-only logic that turns a candidate path into a `Finding`.
/// Used by every path-based module so the safety and skip rules are identical.
struct FindingBuilder: Sendable {
    let category: CleanupCategory
    let risk: Risk
    let safetyGuard: SafetyGuard
    let context: ModuleContext
    let openFiles: OpenFileSnapshot

    /// Returns nil when `SafetyGuard` refuses the path; such items are never shown.
    func make(
        _ url: URL,
        group: String,
        duplicateSet: String? = nil,
        relatedPaths: [URL] = [],
        lastOpened: Date? = nil
    ) -> Finding? {
        guard let validated = try? safetyGuard.validate(url),
              !context.isExcluded(validated.url),
              let size = SizeCalculator.measure(validated.url)
        else { return nil }

        let cutoff = context.now().addingTimeInterval(-context.recentModificationWindow)
        let skip: SkipReason?
        if openFiles.isInUse(validated.url) {
            skip = .inUse
        } else if let newest = size.newestModification, newest > cutoff {
            skip = .recentlyModified
        } else {
            skip = nil
        }

        return Finding(
            category: category,
            target: .path(validated.url),
            group: group,
            reclaimableBytes: size.reclaimableBytes,
            risk: risk,
            skipReason: skip,
            scannedIdentity: validated,
            lastModified: size.newestModification,
            lastOpened: lastOpened,
            duplicateSet: duplicateSet,
            relatedPaths: relatedPaths
        )
    }

    /// Placeholder shown when a location cannot be read without Full Disk Access.
    func needsAccess(_ root: URL, group: String) -> Finding {
        Finding(
            category: category,
            target: .path(root),
            group: group,
            reclaimableBytes: 0,
            risk: risk,
            skipReason: .needsFullDiskAccess
        )
    }

    /// Measures many candidates concurrently.
    func makeAll(_ candidates: [(url: URL, group: String)]) async -> [Finding] {
        await withTaskGroup(of: Finding?.self) { group in
            for candidate in candidates {
                group.addTask { make(candidate.url, group: candidate.group) }
            }
            var findings: [Finding] = []
            for await finding in group {
                if let finding { findings.append(finding) }
            }
            return findings.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
        }
    }

    static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == NSFileReadNoPermissionError { return true }
        if let posix = ns.userInfo[NSUnderlyingErrorKey] as? NSError, posix.domain == NSPOSIXErrorDomain {
            return posix.code == Int(EPERM) || posix.code == Int(EACCES)
        }
        return false
    }
}
