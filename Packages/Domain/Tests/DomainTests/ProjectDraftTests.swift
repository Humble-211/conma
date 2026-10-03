import XCTest
@testable import Domain

final class ProjectDraftTests: XCTestCase {
    func testEmptyDraft() {
        let d = ProjectDraft()
        XCTAssertTrue(d.isEmpty)
        XCTAssertEqual(d.step, 1)
        XCTAssertEqual(d.labourMode, .quick)
        XCTAssertNil(d.jobType)
        XCTAssertTrue(d.schedule.isEmpty)
    }

    func testIsEmptyFalseWhenAnyFieldSet() {
        var d = ProjectDraft(); d.jobType = .kitchen
        XCTAssertFalse(d.isEmpty)
        d = ProjectDraft(); d.address = Address(line: "1 Main", unit: nil, city: nil, region: nil, postalCode: nil)
        XCTAssertFalse(d.isEmpty)
        d = ProjectDraft(); d.step = 5
        XCTAssertTrue(d.isEmpty, "step alone does not make a draft")
    }

    func testBlankAddressIsEmpty() {
        var d = ProjectDraft(); d.address = Address(line: "", unit: nil, city: nil, region: nil, postalCode: nil)
        XCTAssertTrue(d.isEmpty)
        d.address = Address(line: "", unit: nil, city: "Calgary", region: nil, postalCode: nil)
        XCTAssertFalse(d.isEmpty)
    }

    func testBlankNewCustomerIsEmpty() {
        var d = ProjectDraft()
        d.customer = .new(NewCustomerInput(name: "", phone: nil, email: nil, preferredContact: nil, companyName: nil, secondaryContact: nil, notes: nil))
        XCTAssertTrue(d.isEmpty)
        d.customer = .new(NewCustomerInput(name: "Ann", phone: nil, email: nil, preferredContact: nil, companyName: nil, secondaryContact: nil, notes: nil))
        XCTAssertFalse(d.isEmpty)
        d.customer = .existing(UUID())
        XCTAssertFalse(d.isEmpty)
    }

    func testBlankCustomJobTypeIsEmpty() {
        var d = ProjectDraft(); d.customJobType = "  "
        XCTAssertTrue(d.isEmpty)
        d.customJobType = "Sauna"
        XCTAssertFalse(d.isEmpty)
    }

    func testCodableRoundTrip() throws {
        var d = ProjectDraft()
        d.jobType = .other; d.customJobType = "Sauna"
        d.customer = .new(NewCustomerInput(name: "Ann", phone: "416", email: nil, preferredContact: .text, companyName: nil, secondaryContact: nil, notes: nil))
        d.address = Address(line: "123 Main", unit: "2", city: "Toronto", region: "ON", postalCode: "M1M")
        d.scopeFields = [DraftScopeField(id: UUID(), key: "squareFootage", value: "1200", sortOrder: 0)]
        d.startDate = CalendarDate(storage: "2026-10-01"); d.estimatedCompletionDate = CalendarDate(storage: "2026-10-20")
        d.hoursPerDay = Decimal(string: "8.5")
        d.labourMode = .detailed
        d.labourLines = [DraftEstimateLine(id: UUID(), label: "Mike", amount: Money(2000, .cad), quantity: 8, unitRate: Money(250, .cad), costGroup: .labour, otherKind: nil, sortOrder: 0)]
        d.otherLines = [DraftEstimateLine(id: UUID(), label: "Dumpster", amount: Money(400, .cad), quantity: nil, unitRate: nil, costGroup: .other, otherKind: .dumpster, sortOrder: 0)]
        d.contractValue = Money(30_000, .cad)
        d.deposit = DraftDeposit(mode: .percentage(try Percentage.input(20)), deadline: CalendarDate(storage: "2026-10-10"), requiredToStart: true)
        d.scheduleTemplate = .fourStage
        d.schedule = [DraftScheduleRow(id: UUID(), label: "schedule.row.deposit", percentage: try Percentage.input(20), amount: Money(6000, .cad), dueDate: nil, trigger: nil, isDeposit: true)]
        d.step = 11
        let data = try JSONEncoder().encode(d)
        let back = try JSONDecoder().decode(ProjectDraft.self, from: data)
        XCTAssertEqual(back, d)
    }

    func testOtherCostKindMapping() {
        XCTAssertEqual(OtherCostKind.allCases.count, 11)
        XCTAssertEqual(OtherCostKind.subcontractors.costGroup, .subcontractor)
        XCTAssertEqual(OtherCostKind.equipmentRental.costGroup, .equipment)
        XCTAssertEqual(OtherCostKind.toolRental.costGroup, .equipment)
        XCTAssertEqual(OtherCostKind.permits.costGroup, .permit)
        XCTAssertEqual(OtherCostKind.inspectionFees.costGroup, .permit)
        for k in [OtherCostKind.dumpster, .delivery, .parking, .gas, .wasteDisposal, .other] { XCTAssertEqual(k.costGroup, .other, "\(k)") }
    }

    func testDepositModeCodable() throws {
        let fixed = DraftDeposit(mode: .fixed(Money(5000, .cad)), deadline: nil, requiredToStart: false)
        let back = try JSONDecoder().decode(DraftDeposit.self, from: JSONEncoder().encode(fixed))
        XCTAssertEqual(back, fixed)
    }
}
