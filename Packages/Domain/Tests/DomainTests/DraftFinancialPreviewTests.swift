import XCTest
@testable import Domain

final class DraftFinancialPreviewTests: XCTestCase {
    private func line(_ amount: Decimal, _ group: CostGroup, qty: Decimal? = nil, rate: Decimal? = nil) -> DraftEstimateLine {
        DraftEstimateLine(id: UUID(), label: "l", amount: Money(amount, .cad), quantity: qty, unitRate: rate.map { Money($0, .cad) }, costGroup: group, otherKind: nil, sortOrder: 0)
    }

    func testQuickLabourBecomesOneLine() {
        var d = ProjectDraft()
        d.labourMode = .quick
        d.labourQuick = LabourQuickInput(workers: 4, dailyRate: Money(230, .cad), days: 10)
        let lines = d.allEstimateLines(currency: .cad)
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0].costGroup, .labour)
        XCTAssertEqual(lines[0].quantity, 40)
        XCTAssertEqual(lines[0].unitRate?.storageString, "230.00")
        XCTAssertEqual(lines[0].amount.storageString, "9200.00")
        XCTAssertEqual(lines[0].label, "schedule.row.labourQuick")
    }

    func testQuickLabourIncompleteProducesNoLine() {
        var d = ProjectDraft(); d.labourQuick = LabourQuickInput(workers: 4, dailyRate: nil, days: 10)
        XCTAssertTrue(d.allEstimateLines(currency: .cad).isEmpty)
    }

    func testDetailedLinesRecomputeAmountFromRateAndQuantity() {
        var d = ProjectDraft(); d.labourMode = .detailed
        d.labourLines = [line(1, .labour, qty: Decimal(string: "7.5")!, rate: Decimal(string: "250.01")!), line(500, .labour)]
        let lines = d.allEstimateLines(currency: .cad)
        XCTAssertEqual(lines.map { $0.amount.storageString }, ["1875.08", "500.00"])
    }

    func testPreviewNumbers() throws {
        var d = ProjectDraft()
        d.labourMode = .detailed
        d.labourLines = [line(8000, .labour)]
        d.materialLines = [line(6000, .material)]
        d.otherLines = [line(4000, .other)]
        d.contractValue = Money(30_000, .cad)
        d.deposit = DraftDeposit(mode: .percentage(try Percentage.input(20)), deadline: nil, requiredToStart: true)
        d.schedule = PaymentScheduleTemplate.fourStage.rows(depositPercentage: try Percentage.input(20))
        let p = DraftFinancialPreview.compute(d, currency: .cad)
        XCTAssertEqual(p.estimatedCost.storageString, "18000.00")
        XCTAssertEqual(p.estimateByGroup[.labour]?.storageString, "8000.00")
        XCTAssertNil(p.estimateByGroup[.permit])
        XCTAssertEqual(p.projectedProfit?.storageString, "12000.00")
        XCTAssertEqual(p.projectedMargin?.points, 40)
        XCTAssertEqual(p.scheduleTotal.storageString, "30000.00")
        XCTAssertNil(p.scheduleWarning)
        XCTAssertEqual(p.depositAmount?.storageString, "6000.00")
    }

    func testPreviewWithoutContract() {
        var d = ProjectDraft(); d.materialLines = [line(100, .material)]
        let p = DraftFinancialPreview.compute(d, currency: .cad)
        XCTAssertNil(p.projectedProfit); XCTAssertNil(p.projectedMargin); XCTAssertNil(p.depositAmount)
        XCTAssertEqual(p.estimatedCost.storageString, "100.00")
    }

    func testFixedDepositAndMismatchWarning() throws {
        var d = ProjectDraft()
        d.contractValue = Money(1000, .cad)
        d.deposit = DraftDeposit(mode: .fixed(Money(300, .cad)), deadline: nil, requiredToStart: false)
        d.schedule = [DraftScheduleRow(id: UUID(), label: "a", percentage: try Percentage.input(50), amount: nil, dueDate: nil, trigger: nil, isDeposit: true)]
        let p = DraftFinancialPreview.compute(d, currency: .cad)
        XCTAssertEqual(p.depositAmount?.storageString, "300.00")
        XCTAssertEqual(p.scheduleWarning, .totalMismatch(difference: Money(-500, .cad)))
    }
}
