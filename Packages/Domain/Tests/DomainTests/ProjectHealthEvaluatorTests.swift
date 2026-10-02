import XCTest
@testable import Domain

final class ProjectHealthEvaluatorTests: XCTestCase {
    let today = CalendarDate(storage: "2026-10-10")!
    private func alert(_ level: BudgetAlertLevel, group: CostGroup = .material) -> BudgetAlert {
        BudgetAlert(group: group, level: level, estimate: Money(100, .cad), actual: Money(level == .exceeded ? 125 : 92, .cad),
                    overBy: level == .exceeded ? Money(25, .cad) : nil, percentUsed: Percentage.computed(level == .exceeded ? 125 : 92))
    }
    private func inputs(_ status: ProjectStatus, completion: String? = "2026-10-20", progress: Int = 50, alerts: [BudgetAlert] = [], payments: [PaymentStatus] = []) -> HealthInputs {
        HealthInputs(status: status, estimatedCompletionDate: completion.flatMap { CalendarDate(storage: $0) }, progress: progress, budgetAlerts: alerts, paymentStatuses: payments, today: today)
    }

    func testOnTrack() {
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.inProgress)), ProjectHealth(status: .onTrack, reasons: []))
    }

    func testTerminalIsNil() {
        XCTAssertNil(ProjectHealthEvaluator.evaluate(inputs(.closed, alerts: [alert(.exceeded)])))
        XCTAssertNil(ProjectHealthEvaluator.evaluate(inputs(.cancelled, payments: [.overdue])))
    }

    func testDelayedOnlyInWork() {
        let late = ProjectHealthEvaluator.evaluate(inputs(.inProgress, completion: "2026-10-05"))
        XCTAssertEqual(late?.status, .delayed)
        XCTAssertEqual(late?.reasons, [.pastCompletionDate(daysLate: 5)])
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.awaitingFinalPayment, completion: "2026-10-05"))?.status, .onTrack)
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.completed, completion: "2026-10-05"))?.status, .onTrack)
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.awaitingDeposit, completion: "2026-10-05"))?.status, .onTrack)
    }

    func testDeadlineApproachingWindow() {
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.inProgress, completion: "2026-10-10", progress: 79))?.reasons, [.deadlineApproaching(daysLeft: 0, progress: 79)])
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.inProgress, completion: "2026-10-17", progress: 79))?.status, .atRisk)
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.inProgress, completion: "2026-10-18", progress: 79))?.status, .onTrack)
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.inProgress, completion: "2026-10-17", progress: 80))?.status, .onTrack)
        // Already late: Delayed only, no "approaching" reason.
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.inProgress, completion: "2026-10-09", progress: 10))?.reasons, [.pastCompletionDate(daysLate: 1)])
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.inProgress, completion: nil, progress: 10))?.status, .onTrack)
    }

    func testBudgetSignalsByPhase() {
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.inProgress, alerts: [alert(.exceeded)]))?.status, .overBudget)
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.completed, alerts: [alert(.exceeded)]))?.status, .overBudget)
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.awaitingDeposit, alerts: [alert(.exceeded)]))?.status, .onTrack)
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.inProgress, alerts: [alert(.nearLimit)]))?.status, .atRisk)
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.awaitingFinalPayment, alerts: [alert(.nearLimit)]))?.status, .atRisk)
    }

    func testPaymentRiskByPhase() {
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.inProgress, payments: [.overdue, .paid]))?.status, .paymentRisk)
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.inProgress, payments: [.overdue, .overdue]))?.reasons, [.paymentOverdue(count: 2)])
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.awaitingFinalPayment, payments: [.overdue]))?.status, .paymentRisk)
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.awaitingDeposit, payments: [.overdue]))?.status, .paymentRisk)
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.estimate, payments: [.overdue]))?.status, .onTrack)
        XCTAssertEqual(ProjectHealthEvaluator.evaluate(inputs(.awaitingApproval, payments: [.overdue]))?.status, .onTrack)
    }

    func testSeverityOrderAndAllReasonsKept() {
        let h = ProjectHealthEvaluator.evaluate(inputs(.inProgress, completion: "2026-10-01", progress: 10, alerts: [alert(.nearLimit, group: .labour), alert(.exceeded)], payments: [.overdue]))
        XCTAssertEqual(h?.status, .overBudget)
        XCTAssertEqual(h?.reasons, [
            .budgetExceeded(.material, overBy: Money(25, .cad)),
            .paymentOverdue(count: 1),
            .pastCompletionDate(daysLate: 9),
            .budgetNearLimit(.labour, percentUsed: Percentage.computed(92)),
        ])
        let h2 = ProjectHealthEvaluator.evaluate(inputs(.inProgress, completion: "2026-10-01", payments: [.overdue]))
        XCTAssertEqual(h2?.status, .paymentRisk)
        XCTAssertEqual(h2?.reasons.count, 2)
    }
}
