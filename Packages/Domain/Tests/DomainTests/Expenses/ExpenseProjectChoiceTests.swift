import XCTest
@testable import Domain

final class ExpenseProjectChoiceTests: XCTestCase {
    func testSeedDefaultsToBasement() {
        XCTAssertEqual(ExpenseProjectChoice.defaultProject(expenses: Ex.seed(), projects: [Ex.basement, Ex.kitchen, Ex.roof]), Ex.basement.id)
    }

    func testLatestCreatedWinsOverSpentDate() {
        let later = Ex.expense(Ex.kitchen, .fuel, amount: "1.00", tax: "0.00", on: "2026-09-01", createdAt: Fx.now.addingTimeInterval(60))
        XCTAssertEqual(ExpenseProjectChoice.defaultProject(expenses: Ex.seed() + [later], projects: [Ex.basement, Ex.kitchen, Ex.roof]), Ex.kitchen.id)
    }

    func testClosedProjectFallsBackToMostRecentInWork() {
        let closed = Fx.project("Old Deck", customer: Fx.customer("Z"), status: .closed, contract: 1, progress: nil, start: nil, end: nil)
        let bathroom = Fx.project("Bathroom", customer: Fx.customer("Y"), status: .onHold, contract: 1, progress: nil, start: nil, end: nil, updatedAt: Fx.now.addingTimeInterval(120))
        let e = [Ex.expense(closed, .fuel, amount: "1.00", tax: "0.00", on: "2026-10-01", createdAt: Fx.now.addingTimeInterval(300))]
        XCTAssertEqual(ExpenseProjectChoice.defaultProject(expenses: e, projects: [Ex.basement, bathroom, closed]), bathroom.id)
    }

    func testNoInWorkProjectGivesNil() {
        XCTAssertNil(ExpenseProjectChoice.defaultProject(expenses: [], projects: [Ex.kitchen, Ex.roof]))
    }

    func testOrderedByPhaseThenName() {
        let closed = Fx.project("A Closed", customer: Fx.customer("Z"), status: .closed, contract: 1, progress: nil, start: nil, end: nil)
        var deleted = Fx.project("Gone", customer: Fx.customer("Z"), status: .inProgress, contract: 1, progress: nil, start: nil, end: nil)
        deleted.deletedAt = Fx.now
        XCTAssertEqual(ExpenseProjectChoice.ordered([closed, Ex.roof, deleted, Ex.kitchen, Ex.basement]).map(\.name),
                       ["Basement Renovation", "Kitchen Renovation", "Roof Replacement", "A Closed"])
    }
}
