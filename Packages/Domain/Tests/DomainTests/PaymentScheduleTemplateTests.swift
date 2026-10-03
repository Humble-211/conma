import XCTest
@testable import Domain

final class PaymentScheduleTemplateTests: XCTestCase {
    private func pts(_ rows: [DraftScheduleRow]) -> [Decimal] { rows.map { $0.percentage?.points ?? -1 } }

    func testDefaultRows() {
        XCTAssertEqual(pts(PaymentScheduleTemplate.depositFinal.rows(depositPercentage: nil)), [30, 70])
        XCTAssertEqual(pts(PaymentScheduleTemplate.depositProgressFinal.rows(depositPercentage: nil)), [30, 40, 30])
        XCTAssertEqual(pts(PaymentScheduleTemplate.fourStage.rows(depositPercentage: nil)), [20, 30, 30, 20])
        XCTAssertEqual(PaymentScheduleTemplate.fourStage.rows(depositPercentage: nil).map(\.label), ["schedule.row.deposit", "schedule.row.stage2", "schedule.row.stage3", "schedule.row.final"])
        XCTAssertEqual(PaymentScheduleTemplate.depositProgressFinal.rows(depositPercentage: nil).map(\.label), ["schedule.row.deposit", "schedule.row.progress", "schedule.row.final"])
    }

    func testFirstRowIsDepositOthersAreNot() {
        let rows = PaymentScheduleTemplate.fourStage.rows(depositPercentage: nil)
        XCTAssertEqual(rows.map(\.isDeposit), [true, false, false, false])
        XCTAssertTrue(rows.allSatisfy { $0.amount == nil && $0.dueDate == nil })
    }

    func testDepositOverrideSplitsRemainderProportionally() throws {
        let rows = PaymentScheduleTemplate.fourStage.rows(depositPercentage: try Percentage.input(25))
        XCTAssertEqual(pts(rows), [25, Decimal(string: "28.13")!, Decimal(string: "28.13")!, Decimal(string: "18.74")!])
        XCTAssertEqual(rows.reduce(Decimal(0)) { $0 + ($1.percentage?.points ?? 0) }, 100)
        XCTAssertEqual(pts(PaymentScheduleTemplate.depositFinal.rows(depositPercentage: try Percentage.input(50))), [50, 50])
        XCTAssertEqual(pts(PaymentScheduleTemplate.depositProgressFinal.rows(depositPercentage: try Percentage.input(10))), [10, Decimal(string: "51.43")!, Decimal(string: "38.57")!])
    }

    func testCustom() throws {
        XCTAssertEqual(PaymentScheduleTemplate.custom.rows(depositPercentage: nil), [])
        let rows = PaymentScheduleTemplate.custom.rows(depositPercentage: try Percentage.input(20))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].percentage?.points, 20)
        XCTAssertTrue(rows[0].isDeposit)
    }

    func testDepositHundredPercentLeavesZeroRows() throws {
        let rows = PaymentScheduleTemplate.depositFinal.rows(depositPercentage: try Percentage.input(100))
        XCTAssertEqual(pts(rows), [100, 0])
    }
}
