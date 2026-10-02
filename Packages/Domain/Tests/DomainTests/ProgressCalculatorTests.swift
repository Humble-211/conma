import XCTest
@testable import Domain

final class ProgressCalculatorTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    private func task(_ status: TaskStatus, deleted: Bool = false) -> ProjectTask {
        ProjectTask(id: UUID(), companyId: UUID(), projectId: UUID(), name: "t", status: status, startDate: nil, dueDate: nil, notes: nil, sortOrder: 0,
                    assignees: [], checklist: [], createdAt: now, updatedAt: now, deletedAt: deleted ? now : nil)
    }

    func testTaskBasedProgressRoundsHalfUp() {
        XCTAssertEqual(ProgressCalculator.percent(tasks: [task(.completed), task(.completed), task(.inProgress), task(.notStarted), task(.blocked)], manualProgress: nil), 40)
        XCTAssertEqual(ProgressCalculator.percent(tasks: [task(.completed), task(.notStarted), task(.notStarted)], manualProgress: nil), 33)
        XCTAssertEqual(ProgressCalculator.percent(tasks: [task(.completed), task(.completed), task(.notStarted)], manualProgress: nil), 67)
        XCTAssertEqual(ProgressCalculator.percent(tasks: [task(.completed)], manualProgress: nil), 100)
    }

    func testNoTasksIsZero() {
        XCTAssertEqual(ProgressCalculator.percent(tasks: [], manualProgress: nil), 0)
    }

    func testAllTasksDeletedIsZero() {
        XCTAssertEqual(ProgressCalculator.percent(tasks: [task(.completed, deleted: true)], manualProgress: nil), 0)
    }

    func testDeletedTasksIgnored() {
        XCTAssertEqual(ProgressCalculator.percent(tasks: [task(.completed), task(.notStarted, deleted: true)], manualProgress: nil), 100)
    }

    func testManualOverrideWins() {
        XCTAssertEqual(ProgressCalculator.percent(tasks: [task(.completed)], manualProgress: 55), 55)
        XCTAssertEqual(ProgressCalculator.percent(tasks: [], manualProgress: 0), 0)
    }
}
