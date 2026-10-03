import XCTest
@testable import Domain

final class ScheduleMathTests: XCTestCase {
    private func row(_ pct: Decimal?, amount: Decimal? = nil) -> DraftScheduleRow {
        DraftScheduleRow(id: UUID(), label: "x", percentage: pct.map { try! Percentage.input($0) }, amount: amount.map { Money($0, .cad) }, dueDate: nil, trigger: nil, isDeposit: false)
    }
    private func amounts(_ r: ScheduleResult) -> [String] { r.rows.map { $0.amount?.storageString ?? "nil" } }

    func testPercentagesProduceAmountsWithResidual() {
        let r = ScheduleMath.recompute(rows: [row(20), row(30), row(30), row(20)], contract: Money(Decimal(string: "30000.01")!, .cad), edited: .none)
        XCTAssertEqual(amounts(r), ["6000.00", "9000.00", "9000.00", "6000.01"])
        XCTAssertEqual(r.total.storageString, "30000.01")
        XCTAssertNil(r.warning)
    }

    func testEditingAmountRecomputesOnlyThatPercentage() {
        let base = ScheduleMath.recompute(rows: [row(50), row(50)], contract: Money(1000, .cad), edited: .none).rows
        var rows = base; rows[1].amount = Money(600, .cad)
        let r = ScheduleMath.recompute(rows: rows, contract: Money(1000, .cad), edited: .amount(1))
        XCTAssertEqual(r.rows[1].percentage?.points, 60)
        XCTAssertEqual(r.rows[0].amount?.storageString, "500.00")
        XCTAssertEqual(r.total.storageString, "1100.00")
        XCTAssertEqual(r.warning, .totalMismatch(difference: Money(100, .cad)))
    }

    func testEditingPercentageRecomputesAllAmounts() {
        var rows = [row(50), row(50)]; rows[0].percentage = try! Percentage.input(40)
        let r = ScheduleMath.recompute(rows: rows, contract: Money(1000, .cad), edited: .percentage(0))
        XCTAssertEqual(amounts(r), ["400.00", "500.00"])
        XCTAssertEqual(r.warning, .totalMismatch(difference: Money(-100, .cad)))
    }

    func testRowsWithoutPercentageKeepTheirAmount() {
        let r = ScheduleMath.recompute(rows: [row(nil, amount: 250), row(50)], contract: Money(1000, .cad), edited: .none)
        XCTAssertEqual(amounts(r), ["250.00", "500.00"])
    }

    func testContractZero() {
        let r = ScheduleMath.recompute(rows: [row(30), row(70)], contract: Money(0, .cad), edited: .none)
        XCTAssertEqual(amounts(r), ["0.00", "0.00"])
        XCTAssertEqual(r.warning, .contractZero)
        var rows = r.rows; rows[0].amount = Money(100, .cad)
        let r2 = ScheduleMath.recompute(rows: rows, contract: Money(0, .cad), edited: .amount(0))
        XCTAssertNil(r2.rows[0].percentage, "no division by zero")
    }

    func testCurrencyMismatchIsReported() {
        let usd = DraftScheduleRow(id: UUID(), label: "x", percentage: nil, amount: Money(100, .usd), dueDate: nil, trigger: nil, isDeposit: false)
        let r = ScheduleMath.recompute(rows: [row(50), usd], contract: Money(1000, .cad), edited: .none)
        XCTAssertEqual(r.warning, .currencyMismatch)
        XCTAssertEqual(r.total.storageString, "500.00")
    }

    func testEmptyRows() {
        let r = ScheduleMath.recompute(rows: [], contract: Money(1000, .cad), edited: .none)
        XCTAssertTrue(r.rows.isEmpty); XCTAssertEqual(r.total.storageString, "0.00"); XCTAssertNil(r.warning)
    }
}
