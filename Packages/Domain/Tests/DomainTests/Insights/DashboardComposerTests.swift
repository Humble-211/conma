import XCTest
@testable import Domain

final class DashboardComposerTests: XCTestCase {
    let company = Company(id: Fx.companyId, name: "N", currencyCode: .cad, createdAt: Fx.now, updatedAt: Fx.now, deletedAt: nil)

    /// Spec §4 seed: Basement + Kitchen (awaitingDeposit, starts today, deposit 5,000 due +7) + Roof (completed, 18,500 unallocated payment).
    func seed() -> (DashboardInputs, basement: Fx.Basement, kitchen: Project, roof: Project) {
        let b = Fx.Basement()
        let david = Fx.customer("David Nguyen"), maria = Fx.customer("Maria Santos")
        let kitchen = Fx.project("Kitchen Renovation", customer: david, status: .awaitingDeposit, contract: 25_000, progress: nil, start: 0, end: 34)
        let roof = Fx.project("Roof Replacement", customer: maria, status: .completed, contract: 18_500, progress: 100, start: -63, end: -44)
        let inputs = DashboardInputs(company: company, projects: [b.project, kitchen, roof], customers: [b.customer, david, maria], estimateLines: b.lines,
                                     scheduleItems: b.items + [Fx.item(kitchen, "schedule.row.deposit", 5000, due: 7, deposit: true)],
                                     expenses: b.expenses, labourEntries: b.labour, payments: b.payments + [Fx.payment(roof, 18_500, item: nil)], today: Fx.today)
        return (inputs, b, kitchen, roof)
    }

    func testTotalsMatchSpec() {
        let d = DashboardComposer.compose(seed().0)
        XCTAssertEqual(d.totals.activeJobs, 1)
        XCTAssertEqual(d.totals.outstanding, Fx.money(55_400))
        XCTAssertEqual(d.totals.collected, Fx.money(26_100))
        XCTAssertEqual(d.totals.spent, Fx.money(10_685))
        XCTAssertEqual(d.totals.cashPosition, Fx.money(15_415))
        XCTAssertEqual(d.totals.excludedCount, 0)
    }

    func testAttentionOrderMatchesSpec() {
        let (inputs, b, kitchen, _) = seed()
        let a = DashboardComposer.compose(inputs).attention
        XCTAssertEqual(a.count, 3)
        guard case .health(let pid, let status, _) = a[0] else { return XCTFail("\(a[0])") }
        XCTAssertEqual(pid, b.project.id); XCTAssertEqual(status, .paymentRisk)
        guard case .paymentOverdue(let pid2, _, let label, let remaining, let daysLate) = a[1] else { return XCTFail("\(a[1])") }
        XCTAssertEqual(pid2, b.project.id); XCTAssertEqual(label, "schedule.row.stage2"); XCTAssertEqual(remaining, Fx.money(11_400)); XCTAssertEqual(daysLate, 5)
        XCTAssertEqual(a[2], .startsToday(projectId: kitchen.id))
        XCTAssertEqual(a.map(\.kind), [.paymentRisk, .paymentOverdue, .startsToday])
    }

    func testCardsGroupedAndTerminalHidden() {
        var (inputs, b, kitchen, roof) = seed()
        let c = Fx.customer("Z")
        let closed = Fx.project("Closed", customer: c, status: .closed, contract: 100, progress: nil, start: nil, end: nil)
        inputs.projects.append(closed); inputs.customers.append(c)
        let d = DashboardComposer.compose(inputs)
        XCTAssertEqual(d.cards.map(\.id), [b.project.id, kitchen.id, roof.id])
        XCTAssertEqual(d.cards.map(\.group), [.inWork, .preStart, .workDone])
        XCTAssertEqual(d.cards[0].customerName, "Ann Lee")
        XCTAssertEqual(d.totals.outstanding, Fx.money(55_400))   // closed project not in totals
    }

    func testInWorkOrderedBySeverityThenUpdatedAt() {
        let c = Fx.customer("X")
        let ok = Fx.project("ok", customer: c, status: .inProgress, contract: 100, progress: nil, start: nil, end: nil, updatedAt: Fx.now.addingTimeInterval(100))
        let late = Fx.project("late", customer: c, status: .inProgress, contract: 100, progress: nil, start: -10, end: -1)
        let inputs = DashboardInputs(company: company, projects: [ok, late], customers: [c], estimateLines: [], scheduleItems: [], expenses: [], labourEntries: [], payments: [], today: Fx.today)
        XCTAssertEqual(DashboardComposer.compose(inputs).cards.map(\.id), [late.id, ok.id])
    }

    func testExcludesForeignCurrencyProject() {
        let c = Fx.customer("X")
        let usd = Fx.project("usd", customer: c, status: .inProgress, contract: 999, progress: nil, start: nil, end: nil, currency: .usd)
        let cad = Fx.project("cad", customer: c, status: .scheduled, contract: 100, progress: nil, start: nil, end: nil)
        let inputs = DashboardInputs(company: company, projects: [usd, cad], customers: [c], estimateLines: [], scheduleItems: [], expenses: [], labourEntries: [], payments: [], today: Fx.today)
        let d = DashboardComposer.compose(inputs)
        XCTAssertEqual(d.totals.excludedCount, 1)
        XCTAssertEqual(d.totals.outstanding, Fx.money(100))
        XCTAssertEqual(d.totals.activeJobs, 2)                     // both inWork (scheduled is inWork); usd project still counts as a job
        XCTAssertEqual(d.cards.count, 2)                           // still shown as a card
        XCTAssertEqual(d.cards.first { $0.id == usd.id }?.insights.financials?.adjustedContract.currency, .usd)
    }

    func testOverdueProjectYieldsSingleDelayedItem() {
        let c = Fx.customer("X")
        let late = Fx.project("late", customer: c, status: .inProgress, contract: 100, progress: nil, start: -10, end: -1)
        let inputs = DashboardInputs(company: company, projects: [late], customers: [c], estimateLines: [], scheduleItems: [], expenses: [], labourEntries: [], payments: [], today: Fx.today)
        let a = DashboardComposer.compose(inputs).attention
        XCTAssertEqual(a.count, 1); XCTAssertEqual(a[0].kind, .delayed)
    }

    func testDueTodayAndKindOrdering() {
        let c = Fx.customer("X")
        let p = Fx.project("p", customer: c, status: .inProgress, contract: 100, progress: nil, start: nil, end: nil)
        let q = Fx.project("q", customer: c, status: .scheduled, contract: 100, progress: nil, start: 0, end: nil)
        let inputs = DashboardInputs(company: company, projects: [p, q], customers: [c], estimateLines: [Fx.line(p, .material, 10)], scheduleItems: [Fx.item(p, "due", 50, due: 0)],
                                     expenses: [Fx.expense(p, .material, amount: 11, tax: 0)], labourEntries: [], payments: [], today: Fx.today)
        let a = DashboardComposer.compose(inputs).attention
        XCTAssertEqual(a.map(\.kind), [.overBudget, .dueToday, .startsToday])
    }

    func testMissingCustomerGivesEmptyName() {
        let c = Fx.customer("X")
        let p = Fx.project("p", customer: c, status: .inProgress, contract: 100, progress: nil, start: nil, end: nil)
        let inputs = DashboardInputs(company: company, projects: [p], customers: [], estimateLines: [], scheduleItems: [], expenses: [], labourEntries: [], payments: [], today: Fx.today)
        XCTAssertEqual(DashboardComposer.compose(inputs).cards[0].customerName, "")
    }

    func testAttentionScheduleItemId() {
        let item = UUID(), project = UUID()
        XCTAssertEqual(AttentionItem.paymentOverdue(projectId: project, itemId: item, label: "x", remaining: Fx.money(1), daysLate: 2).scheduleItemId, item)
        XCTAssertEqual(AttentionItem.paymentDueToday(projectId: project, itemId: item, label: "x", remaining: Fx.money(1)).scheduleItemId, item)
        XCTAssertNil(AttentionItem.startsToday(projectId: project).scheduleItemId)
    }
}
