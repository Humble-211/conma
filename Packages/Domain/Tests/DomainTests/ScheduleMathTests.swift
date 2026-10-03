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

    // MARK: C1 - typed amounts are authoritative

    private func typedScenario() -> [DraftScheduleRow] {
        let contract = Money(10_000, .cad)
        var rows = PaymentScheduleTemplate.depositFinal.rows(depositPercentage: nil)
        rows = ScheduleMath.recompute(rows: rows, contract: contract, edited: .none).rows
        rows[0].amount = Money(Decimal(string: "3333")!, .cad)
        return ScheduleMath.recompute(rows: rows, contract: contract, edited: .amount(0)).rows
    }

    func testNoneNeverOverwritesTypedAmount() {
        let rows = typedScenario()
        XCTAssertEqual(rows[0].percentage?.points, Decimal(string: "33.3"))
        let r = ScheduleMath.recompute(rows: rows, contract: Money(10_000, .cad), edited: .none)
        XCTAssertEqual(amounts(r), ["3333.00", "7000.00"])
    }

    func testRescaleRederivesFromPercentages() {
        let r = ScheduleMath.recompute(rows: typedScenario(), contract: Money(10_000, .cad), edited: .rescale)
        XCTAssertEqual(amounts(r), ["3330.00", "7000.00"])
    }

    func testNoneOnFreshTemplateEqualsRescale() {
        let rows = PaymentScheduleTemplate.fourStage.rows(depositPercentage: nil)
        let c = Money(Decimal(string: "30000.01")!, .cad)
        XCTAssertEqual(ScheduleMath.recompute(rows: rows, contract: c, edited: .none).rows,
                       ScheduleMath.recompute(rows: rows, contract: c, edited: .rescale).rows)
    }

    func testNoneFillsOnlyNilRows() {
        var rows = [row(50, amount: 123), row(30), row(20, amount: 5)]
        rows[1].amount = nil
        let r = ScheduleMath.recompute(rows: rows, contract: Money(1000, .cad), edited: .none)
        XCTAssertEqual(amounts(r), ["123.00", "300.00", "5.00"])
    }

    // MARK: I3 - deposit drives the deposit row

    private func depositRows(_ t: PaymentScheduleTemplate) -> [DraftScheduleRow] { t.rows(depositPercentage: nil) }

    func testFixedDepositDrivesDepositRow() {
        let contract = Money(25_000, .cad)
        let dep = DraftDeposit(mode: .fixed(Money(3000, .cad)), deadline: nil, requiredToStart: false)
        let rows = ScheduleMath.applyDeposit(rows: depositRows(.fourStage), contract: contract, deposit: dep)
        let r = ScheduleMath.recompute(rows: rows, contract: contract, edited: .none)
        XCTAssertEqual(amounts(r), ["3000.00", "8250.00", "8250.00", "5500.00"])
        XCTAssertEqual(r.rows[0].percentage?.points, 12)
        XCTAssertEqual(r.total.storageString, "25000.00")
        XCTAssertNil(r.warning)
    }

    func testPercentageDepositDrivesDepositRow() {
        let contract = Money(25_000, .cad)
        let dep = DraftDeposit(mode: .percentage(try! Percentage.input(10)), deadline: nil, requiredToStart: false)
        let rows = ScheduleMath.applyDeposit(rows: depositRows(.fourStage), contract: contract, deposit: dep)
        let r = ScheduleMath.recompute(rows: rows, contract: contract, edited: .none)
        XCTAssertEqual(r.rows[0].amount?.storageString, "2500.00")
        XCTAssertEqual(r.total.storageString, "25000.00")
        XCTAssertNil(r.warning)
    }

    func testFixedDepositLargerThanContractKeepsTemplateRowsAndWarns() {
        let contract = Money(2000, .cad)
        let base = depositRows(.fourStage)
        let dep = DraftDeposit(mode: .fixed(Money(3000, .cad)), deadline: nil, requiredToStart: false)
        let rows = ScheduleMath.applyDeposit(rows: base, contract: contract, deposit: dep)
        XCTAssertEqual(rows.dropFirst().map(\.percentage), base.dropFirst().map(\.percentage))
        let r = ScheduleMath.recompute(rows: rows, contract: contract, edited: .none)
        XCTAssertEqual(amounts(r), ["3000.00", "600.00", "600.00", "400.00"])
        XCTAssertEqual(r.warning, .totalMismatch(difference: Money(2600, .cad)))
    }

    func testApplyDepositNoOpWithoutDepositOrRow() {
        let rows = [row(50), row(50)]
        XCTAssertEqual(ScheduleMath.applyDeposit(rows: rows, contract: Money(1000, .cad), deposit: nil), rows)
        let dep = DraftDeposit(mode: .fixed(Money(100, .cad)), deadline: nil, requiredToStart: false)
        XCTAssertEqual(ScheduleMath.applyDeposit(rows: rows, contract: Money(1000, .cad), deposit: dep), rows)
    }
}
