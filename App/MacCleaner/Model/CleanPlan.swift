import CleanerCore
import Foundation

/// What to show after a cleanup finishes.
struct CleanOutcome: Identifiable {
    let id = UUID()
    let result: CleanResult
    let dryRun: Bool
    let findings: [UUID: Finding]
}
