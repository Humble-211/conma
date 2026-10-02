import XCTest
@testable import Domain

final class ScheduleSplitterTests: XCTestCase {
    private func pct(_ s: String) -> Percentage { try! Percentage.input(Decimal(string: s)!) }

    func testLastLineTakesResidualWhenTotalIs100() {
        let contract = Money(Decimal(string: "30000.01")!, .cad)
        let amounts = ScheduleSplitter.amounts(of: contract, percentages: [pct("20"), pct("30"), pct("30"), pct("20")])
        XCTAssertEqual(amounts.map(\.storageString), ["6000.00", "9000.00", "9000.00", "6000.01"])
    }

    func testThirdsOfHundredWithResidual() {
        let amounts = ScheduleSplitter.amounts(of: Money(100, .cad), percentages: [pct("33.33"), pct("33.33"), pct("33.34")])
        XCTAssertEqual(amounts.map(\.storageString), ["33.33", "33.33", "33.34"])
    }

    func testNoResidualWhenTotalIsNot100() {
        let amounts = ScheduleSplitter.amounts(of: Money(100, .cad), percentages: [pct("33.33"), pct("33.33"), pct("33.33")])
        XCTAssertEqual(amounts.map(\.storageString), ["33.33", "33.33", "33.33"])
    }

    func testEmptyInput() {
        XCTAssertEqual(ScheduleSplitter.amounts(of: Money(100, .cad), percentages: []), [])
    }
}
