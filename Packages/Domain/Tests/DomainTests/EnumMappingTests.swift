import XCTest
@testable import Domain

final class EnumMappingTests: XCTestCase {
    func testProjectStatusCountAndRawValues() {
        XCTAssertEqual(ProjectStatus.allCases.count, 13)
        XCTAssertEqual(ProjectStatus.awaitingFinalPayment.rawValue, "awaitingFinalPayment")
        XCTAssertEqual(ProjectStatus.waitingForInspection.rawValue, "waitingForInspection")
    }

    func testPhases() {
        XCTAssertEqual([ProjectStatus.estimate, .awaitingApproval, .awaitingDeposit].map(\.phase), [.preStart, .preStart, .preStart])
        XCTAssertEqual([ProjectStatus.scheduled, .inProgress, .onHold, .waitingForInspection, .waitingForMaterial, .waitingForClient].map(\.phase),
                       Array(repeating: .inWork, count: 6))
        XCTAssertEqual([ProjectStatus.completed, .awaitingFinalPayment].map(\.phase), [.workDone, .workDone])
        XCTAssertEqual([ProjectStatus.closed, .cancelled].map(\.phase), [.terminal, .terminal])
    }

    func testJobTypes() {
        XCTAssertEqual(JobType.allCases.count, 20)
        XCTAssertEqual(JobType.deckFence.rawValue, "deckFence")
        XCTAssertEqual(JobType.windowsDoors.rawValue, "windowsDoors")
        XCTAssertEqual(JobType.hvac.rawValue, "hvac")
        XCTAssertEqual(JobType.allCases.last, .other)
    }

    func testExpenseCategoryToCostGroup() {
        XCTAssertEqual(ExpenseCategory.allCases.count, 14)
        XCTAssertEqual(ExpenseCategory.materials.defaultCostGroup, .material)
        XCTAssertEqual(ExpenseCategory.labour.defaultCostGroup, .labour)
        XCTAssertEqual(ExpenseCategory.subcontractor.defaultCostGroup, .subcontractor)
        XCTAssertEqual(ExpenseCategory.equipmentRental.defaultCostGroup, .equipment)
        XCTAssertEqual(ExpenseCategory.toolPurchase.defaultCostGroup, .equipment)
        XCTAssertEqual(ExpenseCategory.permit.defaultCostGroup, .permit)
        XCTAssertEqual(ExpenseCategory.inspection.defaultCostGroup, .permit)
        for c in [ExpenseCategory.delivery, .fuel, .wasteDisposal, .parking, .office, .other] {
            XCTAssertEqual(c.defaultCostGroup, .other, "\(c)")
        }
        XCTAssertNil(ExpenseCategory.custom.defaultCostGroup)
    }

    func testOtherEnumCounts() {
        XCTAssertEqual(TaskStatus.allCases.count, 6)
        XCTAssertEqual(PaymentMethod.allCases.count, 6)
        XCTAssertEqual(PaymentMethod.eTransfer.rawValue, "eTransfer")
        XCTAssertEqual(PhotoCategory.allCases.count, 6)
        XCTAssertEqual(CostGroup.allCases.count, 6)
    }
}
