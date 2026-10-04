import XCTest
@testable import Domain

final class CustomCategoryRulesTests: XCTestCase {
    func testValidatedName() throws {
        let s = Ex.custom("Scaffolding", .equipment)
        XCTAssertThrowsError(try CustomCategoryRules.validatedName("   ", excluding: nil, existing: [s])) { XCTAssertEqual($0 as? DomainError, .emptyName) }
        XCTAssertThrowsError(try CustomCategoryRules.validatedName(" scaffolding ", excluding: nil, existing: [s])) { XCTAssertEqual($0 as? DomainError, .duplicateName) }
        XCTAssertEqual(try CustomCategoryRules.validatedName(" Scaffolding ", excluding: s.id, existing: [s]), "Scaffolding")
        XCTAssertEqual(try CustomCategoryRules.validatedName("Scaffolding", excluding: nil, existing: [Ex.custom("Scaffolding", .other, deleted: true)]), "Scaffolding")
    }

    func testGroupLockedOnceUsed() throws {
        let s = Ex.custom("Scaffolding", .equipment)
        XCTAssertThrowsError(try CustomCategoryRules.update(s, name: "Scaffolding", costGroup: .other, everUsed: true, existing: [s])) {
            XCTAssertEqual($0 as? DomainError, .categoryInUse)
        }
        let renamed = try CustomCategoryRules.update(s, name: "Scaffold", costGroup: .equipment, everUsed: true, existing: [s])
        XCTAssertEqual(renamed.name, "Scaffold")
        XCTAssertEqual(renamed.costGroup, .equipment)
        XCTAssertEqual(try CustomCategoryRules.update(s, name: "Scaffolding", costGroup: .other, everUsed: false, existing: [s]).costGroup, .other)
    }

    func testDeleteBlockedByLiveExpenses() {
        XCTAssertThrowsError(try CustomCategoryRules.checkDelete(liveExpenseCount: 1)) { XCTAssertEqual($0 as? DomainError, .categoryHasExpenses) }
        XCTAssertNoThrow(try CustomCategoryRules.checkDelete(liveExpenseCount: 0))
    }

    func testReceiptRules() {
        XCTAssertNoThrow(try ReceiptRules.validate(pageCount: 10))
        XCTAssertThrowsError(try ReceiptRules.validate(pageCount: 11)) { XCTAssertEqual($0 as? DomainError, .tooManyReceiptPages) }
        XCTAssertEqual(ReceiptRules.acceptedCount(existing: 8, incoming: 5), 2)
        XCTAssertEqual(ReceiptRules.acceptedCount(existing: 10, incoming: 1), 0)
        XCTAssertEqual(ReceiptRules.acceptedCount(existing: 0, incoming: 3), 3)
    }
}
