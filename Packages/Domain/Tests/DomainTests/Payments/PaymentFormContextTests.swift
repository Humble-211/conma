import XCTest
@testable import Domain

final class PaymentFormContextTests: XCTestCase {
    private func options(_ b: Fx.Basement, _ payments: [Payment], excluding: UUID? = nil, items: [PaymentScheduleItem]? = nil) -> [PaymentItemOption] {
        PaymentFormContext.options(items: items ?? b.items, payments: payments, excluding: excluding, today: Fx.today, currency: .cad)
    }

    func testBasementOptions() {
        let b = Fx.Basement()
        let o = options(b, b.payments)
        XCTAssertEqual(o.map(\.status), [.paid, .overdue, .upcoming, .upcoming])
        XCTAssertEqual(o.map(\.remaining.storageString), ["0.00", "11400.00", "11400.00", "7600.00"])
        XCTAssertEqual(o[0].paid, Fx.money(7600))
        XCTAssertEqual(PaymentFormContext.defaultItemId(o), b.items[1].id)
    }

    func testEditingExcludesOwnPayment() {
        let b = Fx.Basement()
        let o = options(b, b.payments, excluding: b.payments[0].id)
        XCTAssertEqual(o[0].paid, Fx.money(0))
        XCTAssertEqual(o[0].remaining, Fx.money(7600))
        XCTAssertEqual(o[0].status, .overdue)                                    // due −20
        XCTAssertEqual(PaymentFormContext.defaultItemId(o), b.items[0].id)
        XCTAssertNil(PaymentFormContext.overpayment(amount: 7600, option: o[0]))  // re-saving 7,600 is not an overpayment
        XCTAssertEqual(PaymentFormContext.outstanding(project: b.project, payments: b.payments, excluding: b.payments[0].id), Fx.money(38_000))
        XCTAssertEqual(PaymentFormContext.outstanding(project: b.project, payments: b.payments, excluding: nil), Fx.money(30_400))
    }

    func testSuggestions() {
        let b = Fx.Basement()
        let o = options(b, b.payments + [Pay.payment(b.project, "5000.00", item: b.items[1].id)])
        XCTAssertEqual(o[1].status, .overdue)                                    // part-paid but past due: overdue wins (Foundation §5.4 row 2)
        XCTAssertEqual(PaymentFormContext.suggestions(option: o[1], outstanding: nil), [.remaining(Fx.money(6400)), .fullItem(Fx.money(11_400))])
        XCTAssertEqual(PaymentFormContext.suggestions(option: o[2], outstanding: nil), [.remaining(Fx.money(11_400))])
        XCTAssertEqual(PaymentFormContext.suggestions(option: o[0], outstanding: Fx.money(1)), [])
        XCTAssertEqual(PaymentFormContext.suggestions(option: nil, outstanding: Fx.money(30_400)), [.outstanding(Fx.money(30_400))])
        XCTAssertEqual(PaymentFormContext.suggestions(option: nil, outstanding: Fx.money(0)), [])
        XCTAssertEqual(PaymentFormContext.suggestions(option: nil, outstanding: nil), [])
        XCTAssertEqual(PaymentSuggestion.fullItem(Fx.money(3)).money, Fx.money(3))
    }

    func testOverpaymentMarksItemPaidWithoutSpill() {
        let b = Fx.Basement()
        let o = options(b, b.payments)
        XCTAssertEqual(PaymentFormContext.overpayment(amount: 12_000, option: o[1]), Fx.money(600))
        XCTAssertNil(PaymentFormContext.overpayment(amount: 11_400, option: o[1]))
        XCTAssertNil(PaymentFormContext.overpayment(amount: 12_000, option: nil))
        XCTAssertNil(PaymentFormContext.overpayment(amount: nil, option: o[1]))
        let paid = b.payments + [Pay.payment(b.project, "12000.00", item: b.items[1].id)]
        let after = options(b, paid)
        XCTAssertEqual(after.map(\.status), [.paid, .paid, .upcoming, .upcoming])
        XCTAssertEqual(after[2].paid, Fx.money(0))                               // the 600 extra never moves to stage 3
        let insights = ProjectInsightsComposer.compose(ProjectInsightsInputs(project: b.project, estimateLines: b.lines, scheduleItems: b.items, expenses: b.expenses,
                                                                             labourEntries: b.labour, payments: paid, today: Fx.today))
        XCTAssertEqual(insights.financials?.collected, Fx.money(19_600))
        XCTAssertEqual(insights.financials?.outstandingBalance, Fx.money(18_400))
    }

    func testDeletedItemsAndPaymentsIgnored() {
        let b = Fx.Basement()
        var items = b.items
        items[3].deletedAt = Fx.now
        let o = options(b, b.payments + [Pay.payment(b.project, "100.00", item: b.items[1].id, deletedAt: Fx.now)], items: items)
        XCTAssertEqual(o.count, 3)
        XCTAssertEqual(o[1].paid, Fx.money(0))
        XCTAssertEqual(o.map(\.item.sortOrder), [0, 1, 2])
    }
}
