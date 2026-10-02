import XCTest
@testable import Domain

final class MoneyTests: XCTestCase {
    private func cad(_ s: String) -> Money { Money(Decimal(string: s)!, .cad) }

    func testRoundingHalfAwayFromZero() {
        XCTAssertEqual(Money.rounded(Decimal(string: "0.005")!), Decimal(string: "0.01")!)
        XCTAssertEqual(Money.rounded(Decimal(string: "0.004")!), Decimal(string: "0.00")!)
        XCTAssertEqual(Money.rounded(Decimal(string: "2.675")!), Decimal(string: "2.68")!)
        XCTAssertEqual(Money.rounded(Decimal(string: "-0.005")!), Decimal(string: "-0.01")!)
    }

    func testInitRoundsToTwoDecimals() {
        XCTAssertEqual(cad("12.345").amount, Decimal(string: "12.35")!)
        XCTAssertEqual(cad("12.344").storageString, "12.34")
    }

    func testStorageStringAlwaysHasTwoDecimals() {
        XCTAssertEqual(cad("5").storageString, "5.00")
        XCTAssertEqual(cad("5.5").storageString, "5.50")
        XCTAssertEqual(cad("0").storageString, "0.00")
        XCTAssertEqual(cad("-3.4").storageString, "-3.40")
        XCTAssertEqual(cad("1234567.89").storageString, "1234567.89")
    }

    func testStorageRoundTrip() {
        let m = Money(storage: "246.50", currency: .cad)
        XCTAssertEqual(m?.amount, Decimal(string: "246.50")!)
        XCTAssertEqual(m?.storageString, "246.50")
    }

    func testStorageRejectsMalformedStrings() {
        XCTAssertNil(Money(storage: "1,000.5", currency: .cad))
        XCTAssertNil(Money(storage: " 12.345 ", currency: .cad))
        XCTAssertNil(Money(storage: "12.345", currency: .cad))
        XCTAssertNil(Money(storage: "abc", currency: .cad))
        XCTAssertNil(Money(storage: "", currency: .cad))
        XCTAssertNotNil(Money(storage: "-12.30", currency: .cad))
    }

    func testAddSubtractExact() throws {
        let a = cad("0.10"), b = cad("0.20")
        XCTAssertEqual(try a.adding(b).storageString, "0.30")
        XCTAssertEqual(try a.subtracting(b).storageString, "-0.10")
    }

    func testMultiplyRounds() {
        XCTAssertEqual(cad("250.00").multiplied(by: Decimal(string: "0.5")!).storageString, "125.00")
        XCTAssertEqual(cad("10.00").multiplied(by: Decimal(string: "0.3333")!).storageString, "3.33")
        XCTAssertEqual(cad("0.01").multiplied(by: Decimal(string: "0.5")!).storageString, "0.01")
    }

    func testSumIsSumOfRoundedLines() throws {
        let lines = [cad("0.333"), cad("0.333"), cad("0.333")]
        XCTAssertEqual(try Money.sum(lines, currency: .cad).storageString, "0.99")
        XCTAssertEqual(try Money.sum([], currency: .usd), Money.zero(.usd))
    }

    func testCurrencyMismatchThrows() {
        let a = cad("1.00"), b = Money(1, .usd)
        XCTAssertThrowsError(try a.adding(b)) { XCTAssertEqual($0 as? DomainError, .currencyMismatch) }
        XCTAssertThrowsError(try a.subtracting(b)) { XCTAssertEqual($0 as? DomainError, .currencyMismatch) }
        XCTAssertThrowsError(try Money.sum([a, b], currency: .cad)) { XCTAssertEqual($0 as? DomainError, .currencyMismatch) }
    }

    func testSignFlags() {
        XCTAssertTrue(cad("-0.01").isNegative)
        XCTAssertFalse(cad("0.00").isNegative)
        XCTAssertTrue(cad("0.00").isZero)
    }

    func testCodableRoundTrip() throws {
        let original = Money(Decimal(string: "246.50")!, .cad)
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Money.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testCodableRejectsNonCanonicalAmount() throws {
        let json = """
        {"amount":"1.005","currency":"CAD"}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        XCTAssertThrowsError(try decoder.decode(Money.self, from: json)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testCodableDecodesCanonicalForm() throws {
        let json = """
        {"amount":"12.30","currency":"USD"}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Money.self, from: json)
        XCTAssertEqual(decoded.storageString, "12.30")
        XCTAssertEqual(decoded.currency, .usd)
    }
}
