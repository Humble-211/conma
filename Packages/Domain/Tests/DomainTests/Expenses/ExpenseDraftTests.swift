import XCTest
@testable import Domain

final class ExpenseDraftTests: XCTestCase {
    func draft(amount: String?, tax: TaxInput = .none, category: ExpenseCategoryChoice? = .standard(.fuel)) -> ExpenseDraft {
        var d = ExpenseDraft(projectId: Ex.basement.id, spentOn: Fx.today, defaultTaxPercent: nil)
        d.amount = amount.flatMap { Decimal(string: $0) }
        d.tax = tax
        d.category = category
        return d
    }

    func testTaxPercentRounding() {
        XCTAssertEqual(draft(amount: "100", tax: .percent(13)).taxMoney(currency: .cad), Fx.moneyS("13.00"))
        XCTAssertEqual(draft(amount: "100", tax: .percent(13)).total(currency: .cad), Fx.moneyS("113.00"))
        XCTAssertEqual(draft(amount: "99.99", tax: .percent(13)).taxMoney(currency: .cad), Fx.moneyS("13.00"))   // 12.9987
        XCTAssertEqual(draft(amount: "0.10", tax: .percent(5)).taxMoney(currency: .cad), Fx.moneyS("0.01"))      // 0.005 half away
        XCTAssertEqual(draft(amount: "2400", tax: .percent(13)).taxMoney(currency: .cad), Fx.moneyS("312.00"))
        XCTAssertNil(draft(amount: "100", tax: .percent(Decimal(string: "13.125")!)).taxMoney(currency: .cad))
        XCTAssertEqual(draft(amount: "100", tax: .percent(Decimal(string: "13.125")!)).errors, [.taxPercentOutOfRange])
        XCTAssertEqual(draft(amount: "100", tax: .percent(Decimal(string: "100.5")!)).errors, [.taxPercentOutOfRange])
        XCTAssertNil(draft(amount: nil, tax: .percent(13)).taxMoney(currency: .cad))
        XCTAssertEqual(draft(amount: "100", tax: .amount(Decimal(string: "13.456")!)).taxMoney(currency: .cad), Fx.moneyS("13.46"))
    }

    func testDefaultTaxPrefillsPercentMode() {
        XCTAssertEqual(ExpenseDraft(projectId: nil, spentOn: Fx.today, defaultTaxPercent: 13).tax, .percent(13))
        XCTAssertEqual(ExpenseDraft(projectId: nil, spentOn: Fx.today, defaultTaxPercent: nil).tax, TaxInput.none)
    }

    func testValidationOrder() {
        var d = ExpenseDraft(projectId: nil, spentOn: Fx.today, defaultTaxPercent: nil)
        XCTAssertEqual(d.errors, [.projectMissing, .amountMissing, .categoryMissing])
        d.amount = 0
        d.tax = .amount(-1)
        XCTAssertEqual(d.errors, [.projectMissing, .amountNotPositive, .categoryMissing, .taxNegative])
        XCTAssertFalse(d.canSave)
        XCTAssertEqual(draft(amount: "0.004").errors, [.amountNotPositive])
        XCTAssertTrue(draft(amount: "250").canSave)
    }

    func testMakeExpenseBuiltIn() throws {
        var d = draft(amount: "250")
        d.vendorName = "  Esso "
        d.notes = "   "
        d.paymentMethod = .cash
        let id = UUID()
        let e = try d.makeExpense(id: id, companyId: Fx.companyId, currency: .cad, customCategories: [], now: Fx.now)
        XCTAssertEqual(e.id, id)
        XCTAssertEqual(e.category, .fuel)
        XCTAssertEqual(e.costGroup, .other)
        XCTAssertNil(e.customCategoryId)
        XCTAssertEqual(e.amount, Fx.moneyS("250.00"))
        XCTAssertEqual(e.tax, .zero(.cad))
        XCTAssertEqual(e.vendorName, "Esso")
        XCTAssertNil(e.notes)
        XCTAssertEqual(e.paymentMethod, .cash)
        XCTAssertEqual(e.spentOn, Fx.today)
        XCTAssertEqual(e.projectId, Ex.basement.id)
        XCTAssertEqual(e.createdAt, Fx.now)
        XCTAssertNoThrow(try e.validate())
    }

    func testMakeExpenseCustomAndErrors() throws {
        let scaffolding = Ex.custom("Scaffolding", .equipment)
        let e = try draft(amount: "40", category: .custom(scaffolding.id))
            .makeExpense(id: UUID(), companyId: Fx.companyId, currency: .cad, customCategories: [scaffolding], now: Fx.now)
        XCTAssertEqual(e.category, .custom)
        XCTAssertEqual(e.customCategoryId, scaffolding.id)
        XCTAssertEqual(e.costGroup, .equipment)
        let gone = Ex.custom("Gone", .other, deleted: true)
        XCTAssertThrowsError(try draft(amount: "40", category: .custom(gone.id)).makeExpense(id: UUID(), companyId: Fx.companyId, currency: .cad, customCategories: [gone], now: Fx.now)) {
            XCTAssertEqual($0 as? DomainError, .notFound)
        }
        XCTAssertThrowsError(try draft(amount: nil).makeExpense(id: UUID(), companyId: Fx.companyId, currency: .cad, customCategories: [], now: Fx.now)) {
            XCTAssertEqual($0 as? DomainError, .incompleteExpense)
        }
    }

    func testApplyKeepsGroupWhenCategoryUnchanged() throws {
        var scaffolding = Ex.custom("Scaffolding", .equipment)
        let original = try draft(amount: "40", category: .custom(scaffolding.id))
            .makeExpense(id: UUID(), companyId: Fx.companyId, currency: .cad, customCategories: [scaffolding], now: Fx.now)
        scaffolding.costGroup = .other                         // stale/changed group must not regroup history
        var edit = ExpenseDraft(editing: original)
        edit.amount = 45
        let later = Fx.now.addingTimeInterval(60)
        let updated = try edit.apply(to: original, customCategories: [scaffolding], now: later)
        XCTAssertEqual(updated.costGroup, .equipment)
        XCTAssertEqual(updated.amount, Fx.moneyS("45.00"))
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.createdAt, original.createdAt)
        XCTAssertEqual(updated.updatedAt, later)
        edit.category = .standard(.permit)
        XCTAssertEqual(try edit.apply(to: original, customCategories: [scaffolding], now: later).costGroup, .permit)
        edit.category = .standard(.toolPurchase)
        XCTAssertEqual(try edit.apply(to: original, customCategories: [scaffolding], now: later).costGroup, .equipment)
    }

    func testInitEditing() {
        let lumber = Ex.seed()[0]
        let d = ExpenseDraft(editing: lumber)
        XCTAssertEqual(d.tax, .amount(312))
        XCTAssertEqual(d.amount, 2400)
        XCTAssertEqual(d.category, .standard(.materials))
        XCTAssertEqual(d.vendorName, "Lumber — Home Depot")
        XCTAssertEqual(d.notes, "")
        XCTAssertEqual(d.projectId, Ex.basement.id)
        var noTax = lumber
        noTax.tax = .zero(.cad)
        XCTAssertEqual(ExpenseDraft(editing: noTax).tax, TaxInput.none)
    }
}
