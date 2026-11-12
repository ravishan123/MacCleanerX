import Foundation

/// Exactly what a confirmed cleanup will do. Built from the user's selection
/// and shown in the confirmation dialog before anything happens.
public struct CleanPlan: Identifiable, Equatable, Sendable {
    public let id = UUID()
    /// Items removed with the chosen mode (Trash by default).
    public let regular: [Finding]
    /// Items that can't go to the Trash (Trash contents, simulator deletion).
    public let permanentOnly: [Finding]
    public let dryRun: Bool
    /// The "Delete permanently instead of using the Trash" toggle.
    public let permanentToggle: Bool

    public init(findings: [Finding], dryRun: Bool, permanentToggle: Bool) {
        regular = findings.filter { !$0.requiresPermanentDeletion }
        permanentOnly = findings.filter(\.requiresPermanentDeletion)
        self.dryRun = dryRun
        self.permanentToggle = permanentToggle
    }

    public var all: [Finding] { regular + permanentOnly }
    public var count: Int { all.count }
    public var bytes: Int64 { all.reduce(0) { $0 + $1.reclaimableBytes } }
    public var isEmpty: Bool { all.isEmpty }

    public var regularMode: RemovalMode {
        if dryRun { return .dryRun }
        return permanentToggle ? .deletePermanently : .moveToTrash
    }
    public var permanentOnlyMode: RemovalMode { dryRun ? .dryRun : .deletePermanently }

    /// Items that will be permanently deleted if the plan runs.
    public var permanentItems: [Finding] {
        guard !dryRun else { return [] }
        return permanentToggle ? all : permanentOnly
    }
    public var trashItems: [Finding] { dryRun || permanentToggle ? [] : regular }
    public var needsSecondConfirmation: Bool { !permanentItems.isEmpty }
}
