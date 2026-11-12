import Foundation

/// The single code path that removes files. Every module's `clean` goes
/// through here.
///
/// For each finding, immediately before acting:
/// 1. Only `.path` findings are accepted; items flagged as needing Full Disk
///    Access are refused.
/// 2. `SafetyGuard.revalidate` re-checks the path and that it is still the
///    same file that was scanned.
/// 3. In-use and modified-in-the-last-10-minutes checks are repeated.
/// 4. The action runs on the canonical path returned by the guard.
/// Failures are reported per item and never stop the remaining items.
public struct Remover: Sendable {
    public let safetyGuard: SafetyGuard
    public let context: ModuleContext

    public init(safetyGuard: SafetyGuard, context: ModuleContext) {
        self.safetyGuard = safetyGuard
        self.context = context
    }

    public func remove(_ findings: [Finding], mode: RemovalMode) -> CleanResult {
        let openFiles = context.openFiles()
        var result = CleanResult(mode: mode)

        for finding in findings {
            switch prepare(finding, openFiles: openFiles) {
            case .failure(let reason):
                result.failed.append(.init(findingID: finding.id, target: finding.target, reason: reason.message))
            case .success(let (validated, bytes)):
                do {
                    let trashed = try perform(mode, on: validated.url)
                    result.removed.append(.init(findingID: finding.id, target: finding.target, bytes: bytes, trashedURL: trashed))
                } catch {
                    result.failed.append(.init(findingID: finding.id, target: finding.target, reason: error.localizedDescription))
                }
            }
        }
        return result
    }

    struct Refusal: Error {
        let message: String
    }

    private func prepare(_ finding: Finding, openFiles: OpenFileSnapshot) -> Result<(SafetyGuard.ValidatedPath, Int64), Refusal> {
        guard case .path(let url) = finding.target else {
            return .failure(Refusal(message: "Not a file item"))
        }
        if finding.skipReason == .needsFullDiskAccess {
            return .failure(Refusal(message: "Needs Full Disk Access"))
        }

        let validated: SafetyGuard.ValidatedPath
        do throws(SafetyGuard.Rejection) {
            if let scanned = finding.scannedIdentity {
                validated = try safetyGuard.revalidate(scanned)
            } else {
                validated = try safetyGuard.validate(url)
            }
        } catch {
            return .failure(Refusal(message: error.description))
        }

        if context.isExcluded(validated.url) {
            return .failure(Refusal(message: "Excluded in Settings"))
        }
        if openFiles.isInUse(validated.url) {
            return .failure(Refusal(message: "In use by an open app"))
        }
        guard let size = SizeCalculator.measure(validated.url) else {
            return .failure(Refusal(message: SafetyGuard.Rejection.doesNotExist.description))
        }
        if let newest = size.newestModification,
           newest > context.now().addingTimeInterval(-context.recentModificationWindow) {
            return .failure(Refusal(message: "Modified in the last \(Int(context.recentModificationWindow / 60)) minutes"))
        }
        return .success((validated, size.reclaimableBytes))
    }

    private func perform(_ mode: RemovalMode, on url: URL) throws -> URL? {
        switch mode {
        case .dryRun:
            return nil
        case .moveToTrash:
            return try context.operations.moveToTrash(url)
        case .deletePermanently:
            try context.operations.deletePermanently(url)
            return nil
        }
    }
}
