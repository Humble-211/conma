import XCTest
@testable import Domain

final class CategoryRankingTests: XCTestCase {
    func testSeedRanking() {
        XCTAssertEqual(CategoryRanking.mostUsed(expenses: Ex.seed(), customCategories: []),
                       [.standard(.materials), .standard(.wasteDisposal), .standard(.fuel), .standard(.toolPurchase), .standard(.equipmentRental), .standard(.subcontractor)])
    }

    func testEmptyFallsBackToDefaultOrder() {
        XCTAssertEqual(CategoryRanking.mostUsed(expenses: [], customCategories: []),
                       [.standard(.materials), .standard(.fuel), .standard(.toolPurchase), .standard(.equipmentRental), .standard(.subcontractor), .standard(.delivery)])
    }

    func testTieBrokenByMoreRecentUse() {
        let e = [Ex.expense(Ex.basement, .fuel, amount: "10.00", tax: "0.00", on: "2026-10-02"),
                 Ex.expense(Ex.basement, .permit, amount: "10.00", tax: "0.00", on: "2026-10-03")]
        XCTAssertEqual(Array(CategoryRanking.mostUsed(expenses: e, customCategories: []).prefix(3)),
                       [.standard(.permit), .standard(.fuel), .standard(.materials)])
    }

    func testDeletedExpensesAndCategoriesSkipped() {
        let live = Ex.custom("Scaffolding", .equipment), gone = Ex.custom("Old", .other, deleted: true)
        let e = [Ex.expense(Ex.basement, .custom, amount: "1.00", tax: "0.00", on: "2026-10-01", custom: live.id),
                 Ex.expense(Ex.basement, .custom, amount: "1.00", tax: "0.00", on: "2026-10-02", custom: live.id),
                 Ex.expense(Ex.basement, .custom, amount: "1.00", tax: "0.00", on: "2026-10-03", custom: gone.id),
                 Ex.expense(Ex.basement, .parking, amount: "1.00", tax: "0.00", on: "2026-10-03", deletedAt: Fx.now)]
        let r = CategoryRanking.mostUsed(expenses: e, customCategories: [live, gone])
        XCTAssertEqual(r, [.custom(live.id), .standard(.materials), .standard(.fuel), .standard(.toolPurchase), .standard(.equipmentRental), .standard(.subcontractor)])
    }

    func testOnlyLatestFiftyCount() {
        var e = (0..<50).map { i in Ex.expense(Ex.basement, .materials, amount: "1.00", tax: "0.00", on: "2026-10-01", createdAt: Fx.now.addingTimeInterval(TimeInterval(i))) }
        e.append(Ex.expense(Ex.basement, .parking, amount: "1.00", tax: "0.00", on: "2026-01-01"))
        XCTAssertFalse(CategoryRanking.mostUsed(expenses: e, customCategories: []).contains(.standard(.parking)))
    }

    func testChoiceFromExpense() {
        let id = UUID()
        XCTAssertEqual(ExpenseCategoryChoice(Ex.expense(Ex.basement, .custom, amount: "1.00", tax: "0.00", on: "2026-10-01", custom: id)), .custom(id))
        XCTAssertEqual(ExpenseCategoryChoice(Ex.expense(Ex.basement, .custom, amount: "1.00", tax: "0.00", on: "2026-10-01")), .standard(.other))
        XCTAssertEqual(ExpenseCategoryChoice.defaultOrder.count, 13)
        XCTAssertFalse(ExpenseCategoryChoice.defaultOrder.contains(.custom))
    }
}
