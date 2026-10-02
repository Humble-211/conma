import XCTest
@testable import Domain

final class CurrencyCodeTests: XCTestCase {
    func testRawValuesAreISOCodes() {
        XCTAssertEqual(CurrencyCode.cad.rawValue, "CAD")
        XCTAssertEqual(CurrencyCode.usd.rawValue, "USD")
        XCTAssertEqual(CurrencyCode.allCases.count, 2)
    }
}
