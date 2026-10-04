import XCTest
@testable import Domain

final class PaymentListTests: XCTestCase {
    func testRowsNewestFirstWithLabels() {
        let b = Fx.Basement()
        let deposit = Pay.payment(b.project, "7600.00", item: b.items[0].id, on: "2026-09-14")
        let loose = Pay.payment(b.project, "500.00", item: nil, on: "2026-10-02", method: .cash)
        let older = Pay.payment(b.project, "50.00", item: nil, on: "2026-10-02", createdAt: Fx.now.addingTimeInterval(-60))
        let gone = Pay.payment(b.project, "999.00", item: nil, on: "2026-10-03", deletedAt: Fx.now)
        let l = ProjectPaymentListComposer.compose(payments: [deposit, older, loose, gone], scheduleItems: b.items, currency: .cad)
        XCTAssertEqual(l.rows.map(\.payment.amount.storageString), ["500.00", "50.00", "7600.00"])
        XCTAssertEqual(l.rows.map(\.itemLabel), [nil, nil, "schedule.row.deposit"])
        XCTAssertEqual(l.collected, Fx.money(8150))
        XCTAssertEqual(l.unallocated, Fx.money(550))
    }

    func testPaymentOnDeletedItemCountsAsNotLinked() {
        let b = Fx.Basement()
        var items = b.items
        items[1].deletedAt = Fx.now
        let l = ProjectPaymentListComposer.compose(payments: [Pay.payment(b.project, "1000.00", item: b.items[1].id)], scheduleItems: items, currency: .cad)
        XCTAssertNil(l.rows[0].itemLabel)
        XCTAssertEqual(l.unallocated, Fx.money(1000))
    }

    func testEmpty() {
        let l = ProjectPaymentListComposer.compose(payments: [], scheduleItems: [], currency: .cad)
        XCTAssertTrue(l.rows.isEmpty)
        XCTAssertEqual(l.collected, Fx.money(0))
        XCTAssertEqual(l.unallocated, Fx.money(0))
    }
}
