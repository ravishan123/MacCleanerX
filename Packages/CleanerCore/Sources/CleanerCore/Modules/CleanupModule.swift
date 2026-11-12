import Foundation

/// Shared contract for every cleanup module.
///
/// - `scan()` must be read-only: it may enumerate and stat files but never
///   modify, move or delete anything.
/// - `clean(_:mode:)` only acts on findings the user selected and confirmed,
///   and must validate every path through `SafetyGuard` immediately before
///   acting on it.
public protocol CleanupModule: Sendable {
    var category: CleanupCategory { get }
    func scan() async -> [Finding]
    func clean(_ findings: [Finding], mode: RemovalMode) async -> CleanResult
}

extension CleanupModule {
    /// Default is always Move to Trash.
    public func clean(_ findings: [Finding]) async -> CleanResult {
        await clean(findings, mode: .moveToTrash)
    }
}
