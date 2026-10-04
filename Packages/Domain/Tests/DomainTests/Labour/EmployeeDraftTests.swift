import XCTest
@testable import Domain

final class EmployeeDraftTests: XCTestCase {
    func testValidation() {
        var d = EmployeeDraft()
        XCTAssertEqual(d.errors, [.nameMissing])
        d.name = "   "
        XCTAssertEqual(d.errors, [.nameMissing])
        d.name = "Sam"
        d.dailyRate = -1
        XCTAssertEqual(d.errors, [.rateNegative])
        d.dailyRate = nil
        d.hourlyRate = -1
        XCTAssertEqual(d.errors, [.rateNegative])
        d.hourlyRate = nil
        XCTAssertTrue(d.canSave)                                  // the daily rate is optional on the crew form
    }

    func testMakeEmployeeTrimsAndUsesTrade() throws {
        var d = EmployeeDraft()
        d.name = " Sam Patel "
        d.trade = " Electrician "
        d.phone = "  "
        d.dailyRate = 300
        let e = try d.makeEmployee(id: UUID(), companyId: Fx.companyId, currency: .cad, now: Fx.now)
        XCTAssertEqual(e.name, "Sam Patel")
        XCTAssertEqual(e.trade, "Electrician")
        XCTAssertNil(e.role)
        XCTAssertNil(e.phone)
        XCTAssertNil(e.notes)
        XCTAssertEqual(e.dailyRate, Fx.money(300))
        XCTAssertNil(e.hourlyRate)
        XCTAssertEqual(e.createdAt, Fx.now)
        XCTAssertThrowsError(try EmployeeDraft().makeEmployee(id: UUID(), companyId: Fx.companyId, currency: .cad, now: Fx.now)) {
            XCTAssertEqual($0 as? DomainError, .emptyName)
        }
        var negative = d
        negative.dailyRate = -5
        XCTAssertThrowsError(try negative.makeEmployee(id: UUID(), companyId: Fx.companyId, currency: .cad, now: Fx.now)) {
            XCTAssertEqual($0 as? DomainError, .negativeAmount)
        }
    }

    func testDailyFromHourly() {
        var d = EmployeeDraft()
        XCTAssertNil(d.dailyFromHourly)
        d.hourlyRate = Decimal(string: "31.25")
        XCTAssertEqual(d.dailyFromHourly, 250)
        d.hourlyRate = Decimal(string: "28.33")
        XCTAssertEqual(d.dailyFromHourly, Decimal(string: "226.64"))
    }

    func testApplyKeepsHiddenFields() throws {
        var mike = Lab.employee("Mike", rate: "250.00")
        mike.role = "Lead"
        mike.certifications = "WHMIS"
        var d = EmployeeDraft(editing: mike)
        XCTAssertEqual(d.name, "Mike")
        XCTAssertEqual(d.dailyRate, 250)
        d.dailyRate = 275
        let later = Fx.now.addingTimeInterval(5)
        let u = try d.apply(to: mike, currency: .cad, now: later)
        XCTAssertEqual(u.id, mike.id)
        XCTAssertEqual(u.role, "Lead")
        XCTAssertEqual(u.certifications, "WHMIS")
        XCTAssertEqual(u.dailyRate, Fx.money(275))
        XCTAssertEqual(u.createdAt, mike.createdAt)
        XCTAssertEqual(u.updatedAt, later)
    }

    func testCrewListOrder() {
        let a = Lab.employee("mike", rate: nil), b = Lab.employee("David", rate: nil)
        let gone = Lab.employee("Adam", rate: nil, deleted: true), c = Lab.employee("Zoe", rate: nil)
        XCTAssertEqual(CrewList.ordered([a, b, gone, c]).map(\.name), ["David", "mike", "Zoe"])
    }
}
