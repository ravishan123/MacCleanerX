import Foundation
import Testing
@testable import CleanerCore

@Suite("CleanPlan")
struct CleanPlanTests {
    private let cache = Finding(category: .systemCache, target: .path(URL(fileURLWithPath: "/u/Library/Caches/a")),
                                group: "A", reclaimableBytes: 100, risk: .safe)
    private let log = Finding(category: .applicationLogs, target: .path(URL(fileURLWithPath: "/u/Library/Logs/b")),
                              group: "B", reclaimableBytes: 50, risk: .safe)
    private let trash = Finding(category: .trash, target: .path(URL(fileURLWithPath: "/u/.Trash/c")),
                                group: "Trash", reclaimableBytes: 30, risk: .review)
    private let sims = Finding(category: .xcodeJunk, target: .command(.deleteUnavailableSimulators),
                               group: "Simulators", reclaimableBytes: 20, risk: .safe)

    @Test func defaultPlanMovesEverythingToTrashWithOneConfirmation() {
        let plan = CleanPlan(findings: [cache, log], dryRun: false, permanentToggle: false)
        #expect(plan.regularMode == .moveToTrash)
        #expect(plan.count == 2 && plan.bytes == 150)
        #expect(plan.trashItems.count == 2)
        #expect(plan.permanentItems.isEmpty)
        #expect(!plan.needsSecondConfirmation)
    }

    @Test func trashContentsAndSimulatorsAlwaysNeedSecondConfirmation() {
        let plan = CleanPlan(findings: [cache, trash, sims], dryRun: false, permanentToggle: false)
        #expect(plan.regular.map(\.id) == [cache.id])
        #expect(Set(plan.permanentOnly.map(\.id)) == [trash.id, sims.id])
        #expect(plan.permanentOnlyMode == .deletePermanently)
        #expect(plan.regularMode == .moveToTrash)
        #expect(plan.needsSecondConfirmation)
        #expect(plan.permanentItems.count == 2)
    }

    @Test func permanentToggleDeletesEverythingAndNeedsSecondConfirmation() {
        let plan = CleanPlan(findings: [cache, log], dryRun: false, permanentToggle: true)
        #expect(plan.regularMode == .deletePermanently)
        #expect(plan.trashItems.isEmpty)
        #expect(plan.permanentItems.count == 2)
        #expect(plan.needsSecondConfirmation)
    }

    @Test func dryRunNeverDeletesAndSkipsSecondConfirmation() {
        let plan = CleanPlan(findings: [cache, trash, sims], dryRun: true, permanentToggle: true)
        #expect(plan.regularMode == .dryRun)
        #expect(plan.permanentOnlyMode == .dryRun)
        #expect(plan.permanentItems.isEmpty)
        #expect(plan.trashItems.isEmpty)
        #expect(!plan.needsSecondConfirmation)
    }
}
