import XCTest
@testable import Domain

final class PaymentStatusResolverTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let company = UUID(), project = UUID()
    let due = CalendarDate(storage: "2026-10-10")!

    private func item(_ amount: Decimal, due: CalendarDate?) -> PaymentScheduleItem {
        PaymentScheduleItem(id: UUID(), companyId: company, projectId: project, label: "Deposit", amount: Money(amount, .cad), percentage: nil, dueDate: due,
                            triggerText: nil, isDeposit: true, notes: nil, sortOrder: 0, createdAt: now, updatedAt: now, deletedAt: nil)
    }
    private func payment(_ amount: Decimal, item: UUID?, deleted: Bool = false) -> Payment {
        Payment(id: UUID(), companyId: company, projectId: project, scheduleItemId: item, amount: Money(amount, .cad), paidOn: due, method: .cash, notes: nil,
                createdAt: now, updatedAt: now, deletedAt: deleted ? now : nil)
    }
    private func status(_ i: PaymentScheduleItem, paid: Decimal, today: String) -> PaymentStatus {
        PaymentStatusResolver.status(item: i, paidForItem: Money(paid, .cad), today: CalendarDate(storage: today)!)
    }

    func testDateBoundaries() {
        let i = item(5_000, due: due)
        XCTAssertEqual(status(i, paid: 0, today: "2026-10-06"), .upcoming)   // 4 days left
        XCTAssertEqual(status(i, paid: 0, today: "2026-10-07"), .dueSoon)    // 3 days left
        XCTAssertEqual(status(i, paid: 0, today: "2026-10-09"), .dueSoon)    // 1 day left
        XCTAssertEqual(status(i, paid: 0, today: "2026-10-10"), .dueToday)
        XCTAssertEqual(status(i, paid: 0, today: "2026-10-11"), .overdue)
    }

    func testPaidAndOverpaid() {
        let i = item(5_000, due: due)
        XCTAssertEqual(status(i, paid: 5_000, today: "2026-10-20"), .paid)
        XCTAssertEqual(status(i, paid: 6_000, today: "2026-10-20"), .paid)
    }

    func testPartialBeforeAndAfterDue() {
        let i = item(5_000, due: due)
        XCTAssertEqual(status(i, paid: 1_000, today: "2026-10-01"), .partiallyPaid)
        XCTAssertEqual(status(i, paid: 1_000, today: "2026-10-10"), .partiallyPaid) // partial beats dueToday
        XCTAssertEqual(status(i, paid: 1_000, today: "2026-10-11"), .overdue)       // overdue beats partial
    }

    func testNoDueDate() {
        let i = item(5_000, due: nil)
        XCTAssertEqual(status(i, paid: 0, today: "2026-10-01"), .upcoming)
        XCTAssertEqual(status(i, paid: 10, today: "2026-10-01"), .partiallyPaid)
        XCTAssertEqual(status(i, paid: 5_000, today: "2026-10-01"), .paid)
    }

    func testZeroAmountIsAlwaysPaid() {
        XCTAssertEqual(status(item(0, due: due), paid: 0, today: "2026-12-01"), .paid)
    }

    func testAllocation() throws {
        let i = item(5_000, due: due)
        let other = UUID()
        let payments = [payment(1_000, item: i.id), payment(2_000, item: other), payment(500, item: nil), payment(700, item: i.id, deleted: true)]
        XCTAssertEqual(try PaymentAllocation.paidForItem(i.id, payments: payments, currency: .cad).storageString, "1000.00")
        XCTAssertEqual(try PaymentAllocation.collected(payments, currency: .cad).storageString, "3500.00")
    }
}
