// Packages/Domain/Tests/DomainTests/Insights/ProjectInsightsComposerTests.swift
import XCTest
@testable import Domain

final class ProjectInsightsComposerTests: XCTestCase {
    func testBasementSpecNumbers() throws {
        let b = Fx.Basement()
        let i = ProjectInsightsComposer.compose(b.inputs)
        let f = try XCTUnwrap(i.financials)
        XCTAssertEqual(f.estimatedCost, Fx.money(14_800))
        XCTAssertEqual(f.projectedProfit, Fx.money(23_200))
        XCTAssertEqual(f.projectedMargin?.points, Decimal(string: "61.1"))
        XCTAssertEqual(f.spentSoFar, Fx.money(10_685))
        XCTAssertEqual(f.collected, Fx.money(7600))
        XCTAssertEqual(f.outstandingBalance, Fx.money(30_400))
        XCTAssertEqual(f.cashPosition, Fx.money(-3085))
        XCTAssertEqual(f.actualProfit, Fx.money(27_315))
        XCTAssertEqual(f.profitLabel, .projectedAtCurrentSpending)
        XCTAssertEqual(i.budgetAlerts.map(\.group), [.labour])
        XCTAssertEqual(i.budgetAlerts.first?.level, .nearLimit)
        XCTAssertEqual(i.budgetAlerts.first?.percentUsed?.points, Decimal(string: "93.3"))
        XCTAssertEqual(i.payments.map(\.status), [.paid, .overdue, .upcoming, .upcoming])
        XCTAssertEqual(i.payments[0].paid, Fx.money(7600)); XCTAssertEqual(i.payments[0].remaining, .zero(.cad))
        XCTAssertEqual(i.payments[1].remaining, Fx.money(11_400))
        XCTAssertEqual(i.unallocatedCollected, .zero(.cad))
        XCTAssertEqual(i.progress, 65)
        XCTAssertEqual(i.health?.status, .paymentRisk)
        XCTAssertEqual(i.health?.reasons.count, 2)
        XCTAssertEqual(i.timeline.daysElapsed, 18); XCTAssertEqual(i.timeline.daysRemaining, 27)
        XCTAssertEqual(i.timeline.totalDays, 45); XCTAssertEqual(i.timeline.expectedProgress, 40)
    }

    func testFoundationExample() throws {
        let c = Fx.customer("X")
        let p = Fx.project("F", customer: c, status: .inProgress, contract: 30_000, progress: nil, start: nil, end: nil)
        let inputs = ProjectInsightsInputs(project: p, estimateLines: [], scheduleItems: [],
                                           expenses: [Fx.expense(p, .material, amount: 6000, tax: 0), Fx.expense(p, .other, amount: 1000, tax: 0)],
                                           labourEntries: [Fx.labour(p, days: 30, rate: 250)], payments: [Fx.payment(p, 5000, item: nil), Fx.payment(p, 15_000, item: nil)], today: Fx.today)
        let f = try XCTUnwrap(ProjectInsightsComposer.compose(inputs).financials)
        XCTAssertEqual(f.totalCost, Fx.money(14_500)); XCTAssertEqual(f.actualProfit, Fx.money(15_500))
        XCTAssertEqual(f.actualMargin?.points, Decimal(string: "51.7")); XCTAssertEqual(f.outstandingBalance, Fx.money(10_000))
        XCTAssertEqual(ProjectInsightsComposer.compose(inputs).unallocatedCollected, Fx.money(20_000))
    }

    func testCurrencyMismatchYieldsNilFinancials() {
        let c = Fx.customer("X")
        let p = Fx.project("U", customer: c, status: .inProgress, contract: 1000, progress: 10, start: -10, end: -1, currency: .usd)
        let inputs = ProjectInsightsInputs(project: p, estimateLines: [Fx.line(p, .material, 100)], scheduleItems: [], expenses: [], labourEntries: [], payments: [], today: Fx.today)
        let i = ProjectInsightsComposer.compose(inputs)
        XCTAssertNil(i.financials); XCTAssertEqual(i.budgetAlerts, [])
        XCTAssertEqual(i.health?.status, .delayed)           // date rules still run
        XCTAssertEqual(i.timeline.daysRemaining, -1)
    }

    func testPaymentOnDeletedItemIsUnallocated() throws {
        let c = Fx.customer("X")
        let p = Fx.project("D", customer: c, status: .inProgress, contract: 1000, progress: nil, start: nil, end: nil)
        let gone = Fx.item(p, "x", 500, due: nil, deletedAt: Fx.now)
        let live = Fx.item(p, "y", 500, due: nil, order: 1)
        let inputs = ProjectInsightsInputs(project: p, estimateLines: [], scheduleItems: [gone, live], expenses: [], labourEntries: [], payments: [Fx.payment(p, 500, item: gone.id)], today: Fx.today)
        let i = ProjectInsightsComposer.compose(inputs)
        XCTAssertEqual(i.payments.map(\.item.id), [live.id])
        XCTAssertEqual(i.payments[0].paid, .zero(.cad))
        XCTAssertEqual(i.unallocatedCollected, Fx.money(500))
        XCTAssertEqual(try XCTUnwrap(i.financials).collected, Fx.money(500))
    }

    func testDeletedExpenseAndPaymentIgnored() throws {
        let c = Fx.customer("X")
        let p = Fx.project("D", customer: c, status: .inProgress, contract: 1000, progress: nil, start: nil, end: nil)
        let inputs = ProjectInsightsInputs(project: p, estimateLines: [], scheduleItems: [], expenses: [Fx.expense(p, .material, amount: 100, tax: 0, deletedAt: Fx.now)], labourEntries: [], payments: [Fx.payment(p, 100, item: nil, deletedAt: Fx.now)], today: Fx.today)
        let f = try XCTUnwrap(ProjectInsightsComposer.compose(inputs).financials)
        XCTAssertEqual(f.spentSoFar, .zero(.cad)); XCTAssertEqual(f.collected, .zero(.cad))
    }

    func testTimelineEdges() {
        let c = Fx.customer("X")
        func tl(start: Int?, end: Int?, today: Int = 0) -> TimelineInsight {
            let p = Fx.project("T", customer: c, status: .inProgress, contract: 1, progress: nil, start: start, end: end)
            return ProjectInsightsComposer.compose(ProjectInsightsInputs(project: p, estimateLines: [], scheduleItems: [], expenses: [], labourEntries: [], payments: [], today: Fx.day(today))).timeline
        }
        XCTAssertEqual(tl(start: 0, end: 0).totalDays, 0); XCTAssertEqual(tl(start: 0, end: 0).expectedProgress, 100)
        XCTAssertEqual(tl(start: 5, end: 10).daysElapsed, 0); XCTAssertEqual(tl(start: 5, end: 10).expectedProgress, 0)
        XCTAssertEqual(tl(start: -10, end: -2).daysRemaining, -2); XCTAssertEqual(tl(start: -10, end: -2).expectedProgress, 100)
        XCTAssertNil(tl(start: nil, end: 3).daysElapsed); XCTAssertEqual(tl(start: nil, end: 3).daysRemaining, 3); XCTAssertNil(tl(start: nil, end: 3).expectedProgress)
        XCTAssertNil(tl(start: -3, end: nil).daysRemaining); XCTAssertEqual(tl(start: -3, end: nil).daysElapsed, 3)
        XCTAssertEqual(tl(start: -1, end: 2).expectedProgress, 33)   // 1/3 → 33
    }

    func testTimelineRecomputesWithNewToday() {
        let b = Fx.Basement()
        let later = b.inputs.snapshot.with(today: Fx.day(30))
        let i = ProjectInsightsComposer.compose(later)
        XCTAssertEqual(i.timeline.daysRemaining, -3)
        XCTAssertEqual(i.health?.status, .paymentRisk)   // paymentRisk outranks delayed
        XCTAssertTrue(i.health?.reasons.contains(.pastCompletionDate(daysLate: 3)) ?? false)
    }
}
