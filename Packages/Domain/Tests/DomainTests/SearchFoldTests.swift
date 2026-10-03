import XCTest
@testable import Domain

final class SearchFoldTests: XCTestCase {
    func testFoldsVietnameseD() {
        XCTAssertEqual(SearchFold.normalize("Đà Nẵng"), "da nang")
        XCTAssertEqual(SearchFold.normalize("ĐƯỜNG"), "duong")
    }

    func testTrimsAndLowercases() {
        XCTAssertEqual(SearchFold.normalize("  Ann Lee "), "ann lee")
    }

    func testNameContainsFoldedQuery() {
        XCTAssertTrue(SearchFold.normalize("Trần Văn Đức").contains("duc"))
    }
}
