import XCTest
@testable import Domain

final class ExpenseListComposerTests: XCTestCase {
    func snapshot(_ expenses: [Expense], categories: [CustomExpenseCategory] = []) -> ExpenseListSnapshot {
        ExpenseListSnapshot(currency: .cad, expenses: expenses, projects: [Ex.basement, Ex.kitchen, Ex.roof], customCategories: categories)
    }
    func fuel() -> Expense { Ex.expense(Ex.kitchen, .fuel, amount: "80.00", tax: "10.40", on: "2026-08-30", vendor: "Esso", notes: "Đá granite pickup") }

    func testSeedTotalsAndSections() {
        let l = ExpenseListComposer.compose(snapshot(Ex.seed() + [fuel()]), filter: ExpenseFilter(), today: Fx.today)
        XCTAssertEqual(l.thisMonth, Fx.moneyS("1695.00"))
        XCTAssertEqual(l.lastMonth, Fx.moneyS("3390.00"))
        XCTAssertEqual(l.sections.map(\.day.storageString), ["2026-10-01", "2026-09-18", "2026-09-17", "2026-08-30"])
        XCTAssertEqual(l.sections.map(\.total), [Fx.moneyS("1695.00"), Fx.moneyS("2712.00"), Fx.moneyS("678.00"), Fx.moneyS("90.40")])
        XCTAssertEqual(l.rows.map(\.receiptCount), [0, 2, 1, 0])
        XCTAssertEqual(l.rows.first?.projectName, "Basement Renovation")
        XCTAssertEqual(l.rows.last?.projectName, "Kitchen Renovation")
        XCTAssertEqual(l.rows.first?.choice, .standard(.materials))
    }

    func testProjectFilter() {
        let l = ExpenseListComposer.compose(snapshot(Ex.seed() + [fuel()]), filter: ExpenseFilter(projectId: Ex.kitchen.id), today: Fx.today)
        XCTAssertEqual(l.thisMonth, .zero(.cad))
        XCTAssertEqual(l.lastMonth, .zero(.cad))
        XCTAssertEqual(l.sections.map(\.day.storageString), ["2026-08-30"])
    }

    func testCategoryFilter() {
        let l = ExpenseListComposer.compose(snapshot(Ex.seed() + [fuel()]), filter: ExpenseFilter(category: .standard(.materials)), today: Fx.today)
        XCTAssertEqual(l.thisMonth, Fx.moneyS("1695.00"))
        XCTAssertEqual(l.lastMonth, Fx.moneyS("2712.00"))
        XCTAssertEqual(l.rows.count, 2)
    }

    func testSearchVendorAndNotesFolded() {
        let all = snapshot(Ex.seed() + [fuel()])
        func vendors(_ q: String) -> [String] { ExpenseListComposer.compose(all, filter: ExpenseFilter(query: q), today: Fx.today).rows.compactMap(\.expense.vendorName) }
        XCTAssertEqual(vendors("home depot"), ["Lumber — Home Depot"])
        XCTAssertEqual(vendors("DUMP"), ["Dumpster rental"])
        XCTAssertEqual(vendors("da granite"), ["Esso"])
        XCTAssertEqual(vendors("  "), ["Drywall", "Lumber — Home Depot", "Dumpster rental", "Esso"])
        XCTAssertEqual(vendors("zzz"), [])
    }

    func testSearchDoesNotChangeMonthTotals() {
        let l = ExpenseListComposer.compose(snapshot(Ex.seed()), filter: ExpenseFilter(query: "drywall"), today: Fx.today)
        XCTAssertEqual(l.rows.count, 1)
        XCTAssertEqual(l.thisMonth, Fx.moneyS("1695.00"))
        XCTAssertEqual(l.lastMonth, Fx.moneyS("3390.00"))
    }

    func testLastMonthAcrossYearBoundary() {
        let e = [Ex.expense(Ex.basement, .fuel, amount: "10.00", tax: "0.00", on: "2026-12-31"),
                 Ex.expense(Ex.basement, .fuel, amount: "20.00", tax: "0.00", on: "2027-01-02"),
                 Ex.expense(Ex.basement, .fuel, amount: "40.00", tax: "0.00", on: "2026-11-30")]
        let l = ExpenseListComposer.compose(snapshot(e), filter: ExpenseFilter(), today: CalendarDate(storage: "2027-01-05")!)
        XCTAssertEqual(l.thisMonth, Fx.moneyS("20.00"))
        XCTAssertEqual(l.lastMonth, Fx.moneyS("10.00"))
    }

    func testSameDayNewestCreatedFirstAndDeletedIgnored() {
        let first = Ex.expense(Ex.basement, .fuel, amount: "1.00", tax: "0.00", on: "2026-10-02", vendor: "A")
        let second = Ex.expense(Ex.basement, .fuel, amount: "2.00", tax: "0.00", on: "2026-10-02", vendor: "B", createdAt: Fx.now.addingTimeInterval(60))
        let gone = Ex.expense(Ex.basement, .fuel, amount: "4.00", tax: "0.00", on: "2026-10-02", vendor: "C", deletedAt: Fx.now)
        let l = ExpenseListComposer.compose(snapshot([first, second, gone]), filter: ExpenseFilter(), today: Fx.today)
        XCTAssertEqual(l.rows.compactMap(\.expense.vendorName), ["B", "A"])
        XCTAssertEqual(l.sections.first?.total, Fx.moneyS("3.00"))
        XCTAssertEqual(l.thisMonth, Fx.moneyS("3.00"))
    }

    func testCustomCategoryNameKeptAfterDelete() {
        let old = Ex.custom("Old", .other, deleted: true)
        let e = Ex.expense(Ex.basement, .custom, amount: "5.00", tax: "0.00", on: "2026-10-01", custom: old.id)
        let row = ExpenseListComposer.compose(snapshot([e], categories: [old]), filter: ExpenseFilter(), today: Fx.today).rows.first
        XCTAssertEqual(row?.choice, .custom(old.id))
        XCTAssertEqual(row?.customCategoryName, "Old")
    }
}
