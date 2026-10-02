import XCTest
@testable import Domain

final class PercentageTests: XCTestCase {
    func testInputAcceptsRangeAndTwoDecimals() throws {
        XCTAssertEqual(try Percentage.input(10).points, 10)
        XCTAssertEqual(try Percentage.input(0).points, 0)
        XCTAssertEqual(try Percentage.input(100).points, 100)
        XCTAssertEqual(try Percentage.input(Decimal(string: "33.33")!).points, Decimal(string: "33.33")!)
    }

    func testInputRejectsOutOfRangeAndTooManyDecimals() {
        XCTAssertThrowsError(try Percentage.input(-1)) { XCTAssertEqual($0 as? DomainError, .invalidPercentage) }
        XCTAssertThrowsError(try Percentage.input(Decimal(string: "100.01")!)) { XCTAssertEqual($0 as? DomainError, .invalidPercentage) }
        XCTAssertThrowsError(try Percentage.input(Decimal(string: "12.345")!)) { XCTAssertEqual($0 as? DomainError, .invalidPercentage) }
    }

    func testFractionAndMoneyMultiplication() throws {
        let contract = Money(30_000, .cad)
        XCTAssertEqual(contract.multiplied(by: try Percentage.input(10)).storageString, "3000.00")
        XCTAssertEqual(contract.multiplied(by: try Percentage.input(20)).storageString, "6000.00")
        XCTAssertEqual(try Percentage.input(25).fraction, Decimal(string: "0.25")!)
    }

    func testComputedRoundsToOneDecimal() {
        XCTAssertEqual(Percentage.computed(Decimal(string: "51.6666")!).points, Decimal(string: "51.7")!)
        XCTAssertEqual(Percentage.computed(Decimal(string: "-12.35")!).points, Decimal(string: "-12.4")!)
        XCTAssertEqual(Percentage.computed(150).points, 150)
    }

    func testRatio() {
        let profit = Money(15_500, .cad), contract = Money(30_000, .cad)
        XCTAssertEqual(Percentage.ratio(profit, over: contract)?.points, Decimal(string: "51.7")!)
        XCTAssertNil(Percentage.ratio(profit, over: Money.zero(.cad)))
    }
}
