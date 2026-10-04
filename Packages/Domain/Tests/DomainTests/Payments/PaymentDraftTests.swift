import XCTest
@testable import Domain

final class PaymentDraftTests: XCTestCase {
    func testErrors() {
        var d = PaymentDraft(paidOn: Fx.today, method: .eTransfer)
        XCTAssertEqual(d.errors, [.amountMissing])
        d.amount = 0
        XCTAssertEqual(d.errors, [.amountNotPositive])
        d.amount = Decimal(string: "0.004")
        XCTAssertEqual(d.errors, [.amountNotPositive])
        d.amount = -5
        XCTAssertEqual(d.errors, [.amountNotPositive])
        d.amount = Decimal(string: "0.005")
        XCTAssertEqual(d.errors, [])                                  // rounds to 0.01
        XCTAssertTrue(d.canSave)
    }

    func testMakePaymentRoundsOnceAndTrimsNotes() throws {
        let b = Fx.Basement()
        var d = PaymentDraft(paidOn: Fx.today, method: .cheque, scheduleItemId: b.items[1].id, amount: Decimal(string: "11400.005"))
        d.notes = "  cheque #204  "
        let p = try d.makePayment(id: UUID(), companyId: Fx.companyId, projectId: b.project.id, currency: .cad, now: Fx.now)
        XCTAssertEqual(p.amount.storageString, "11400.01")
        XCTAssertEqual(p.notes, "cheque #204")
        XCTAssertEqual(p.method, .cheque)
        XCTAssertEqual(p.scheduleItemId, b.items[1].id)
        XCTAssertEqual(p.projectId, b.project.id)
        XCTAssertEqual(p.createdAt, Fx.now)
        XCTAssertNoThrow(try p.validate())
    }

    func testIncompleteThrows() {
        XCTAssertThrowsError(try PaymentDraft(paidOn: Fx.today, method: .cash).makePayment(id: UUID(), companyId: Fx.companyId, projectId: UUID(), currency: .cad, now: Fx.now)) {
            XCTAssertEqual($0 as? DomainError, .incompletePayment)
        }
    }

    func testApplyKeepsIdentityAndUnlinks() throws {
        let b = Fx.Basement()
        let original = b.payments[0]
        var d = PaymentDraft(editing: original)
        XCTAssertEqual(d.amount, 7600)
        XCTAssertEqual(d.scheduleItemId, b.items[0].id)
        XCTAssertEqual(d.notes, "")
        d.scheduleItemId = nil
        d.amount = 7000
        d.notes = "   "
        let later = Fx.now.addingTimeInterval(60)
        let u = try d.apply(to: original, now: later)
        XCTAssertEqual(u.id, original.id)
        XCTAssertEqual(u.projectId, original.projectId)
        XCTAssertEqual(u.createdAt, original.createdAt)
        XCTAssertEqual(u.updatedAt, later)
        XCTAssertNil(u.scheduleItemId)
        XCTAssertEqual(u.amount, Fx.money(7000))
        XCTAssertNil(u.notes)
    }

    func testDefaultMethodAndOrder() {
        XCTAssertEqual(PaymentDraft.defaultMethod(lastUsed: nil), .eTransfer)
        XCTAssertEqual(PaymentDraft.defaultMethod(lastUsed: .cheque), .cheque)
        XCTAssertEqual(PaymentDraft.methodOrder.first, .eTransfer)
        XCTAssertEqual(PaymentDraft.methodOrder.count, PaymentMethod.allCases.count)
        XCTAssertEqual(Set(PaymentDraft.methodOrder), Set(PaymentMethod.allCases))
    }
}
