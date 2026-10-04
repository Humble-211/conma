import XCTest
@testable import Domain

final class LabourDraftTests: XCTestCase {
    func testToggleSnapshotsRateAndRemoves() {
        let s = Lab.Seed()
        var d = LabourDraft(workDate: Fx.today)
        XCTAssertEqual(d.days, 1)
        d.toggle(s.mike)
        d.toggle(s.john)
        XCTAssertEqual(d.lines.map(\.dailyRate), [250, 220])
        XCTAssertTrue(d.isSelected(s.mike.id))
        d.toggle(s.mike)
        XCTAssertEqual(d.lines.map(\.employeeId), [s.john.id])
        XCTAssertFalse(d.isSelected(s.mike.id))
    }

    func testTwoPeopleTotals() {
        let s = Lab.Seed()
        var d = LabourDraft(workDate: Fx.today)
        XCTAssertNil(d.total(currency: .cad))
        d.toggle(s.mike)
        d.toggle(s.john)
        XCTAssertEqual(d.total(currency: .cad), Fx.money(470))
        d.days = Decimal(string: "1.5")
        XCTAssertEqual(d.cost(for: s.mike.id, currency: .cad), Fx.money(375))
        XCTAssertEqual(d.total(currency: .cad), Fx.money(705))
    }

    func testHalfDayRounding() {
        let odd = Lab.employee("Sam", rate: "333.33")
        var d = LabourDraft(workDate: Fx.today)
        d.toggle(odd)
        d.days = Decimal(string: "0.5")
        XCTAssertEqual(d.cost(for: odd.id, currency: .cad), Fx.moneyS("166.67"))   // 166.665 → half away from zero
        d.toggle(Lab.Seed().mike)
        XCTAssertEqual(d.total(currency: .cad), Fx.moneyS("291.67"))               // 166.67 + 125.00, rounded per person
    }

    func testErrorsInOrderAndZeroRate() {
        var d = LabourDraft(workDate: Fx.today)
        d.days = nil
        XCTAssertEqual(d.errors, [.noCrewSelected, .daysMissing])
        let noRate = Lab.employee("Pat", rate: nil)
        d.toggle(noRate)
        d.days = 0
        XCTAssertEqual(d.errors, [.daysNotPositive, .rateMissing])
        XCTAssertEqual(d.lineError(for: noRate.id), .rateMissing)
        XCTAssertNil(d.cost(for: noRate.id, currency: .cad))
        d.setRate(-1, for: noRate.id)
        d.days = 1
        XCTAssertEqual(d.errors, [.rateNegative])
        d.setRate(0, for: noRate.id)
        XCTAssertTrue(d.canSave)                                                     // $0 allowed (an owner's own day)
        XCTAssertEqual(d.total(currency: .cad), Fx.money(0))
    }

    func testStepDays() {
        var d = LabourDraft(workDate: Fx.today)
        d.stepDays(up: true)
        XCTAssertEqual(d.days, Decimal(string: "1.5"))
        d.stepDays(up: false)
        d.stepDays(up: false)
        XCTAssertEqual(d.days, Decimal(string: "0.5"))
        d.stepDays(up: false)
        XCTAssertEqual(d.days, Decimal(string: "0.5"))
        d.days = nil
        d.stepDays(up: true)
        XCTAssertEqual(d.days, Decimal(string: "0.5"))
    }

    func testStepDownNeverRaisesBelowFloor() {
        var d = LabourDraft(workDate: Fx.today)
        d.days = Decimal(string: "0.25")
        d.stepDays(up: false)
        XCTAssertEqual(d.days, Decimal(string: "0.25"))
        d.days = Decimal(string: "0.5")
        d.stepDays(up: false)
        XCTAssertEqual(d.days, Decimal(string: "0.5"))
        d.days = Decimal(string: "0.75")
        d.stepDays(up: false)
        XCTAssertEqual(d.days, Decimal(string: "0.5"))
        d.days = Decimal(string: "0.25")
        d.stepDays(up: true)
        XCTAssertEqual(d.days, Decimal(string: "0.75"))
    }

    func testDaysRoundedToTwoDecimalsForCostAndEntries() throws {
        let s = Lab.Seed()
        var d = LabourDraft(workDate: Fx.today)
        d.toggle(s.mike)                                                             // 250.00 / day
        d.days = Decimal(string: "0.333")
        XCTAssertEqual(d.roundedDays, Decimal(string: "0.33"))
        XCTAssertEqual(d.cost(for: s.mike.id, currency: .cad), Fx.moneyS("82.50"))   // not 83.25
        XCTAssertEqual(d.total(currency: .cad), Fx.moneyS("82.50"))
        let entries = try d.makeEntries(companyId: Fx.companyId, projectId: s.project.id, currency: .cad, now: Fx.now)
        XCTAssertEqual(entries.map(\.days), [Decimal(string: "0.33")])
        XCTAssertEqual(entries.map(\.cost), [Fx.moneyS("82.50")])
        d.days = Decimal(string: "0.125")                                           // half away from zero
        XCTAssertEqual(d.roundedDays, Decimal(string: "0.13"))
        d.days = Decimal(string: "0.004")                                           // rounds to 0 → not positive
        XCTAssertEqual(d.errors, [.daysNotPositive])
    }

    func testApplyRoundsDays() throws {
        let s = Lab.Seed()
        let david = s.entries[2]                                                     // 200.00 / day
        var d = LabourDraft(editing: david)
        d.days = Decimal(string: "2.666")
        let u = try d.apply(to: david, now: Fx.now)
        XCTAssertEqual(u.days, Decimal(string: "2.67"))
        XCTAssertEqual(u.cost, Fx.moneyS("534.00"))
    }

    func testMakeEntriesOnePerPerson() throws {
        let s = Lab.Seed()
        var d = LabourDraft(workDate: Fx.today)
        d.toggle(s.mike)
        d.toggle(s.john)
        d.notes = "  framing  "
        let entries = try d.makeEntries(companyId: Fx.companyId, projectId: s.project.id, currency: .cad, now: Fx.now)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(Set(entries.map(\.id)).count, 2)
        XCTAssertEqual(entries.map(\.employeeId), [s.mike.id, s.john.id])
        XCTAssertEqual(entries.map(\.dailyRate), [Fx.money(250), Fx.money(220)])
        XCTAssertTrue(entries.allSatisfy { $0.workDate == Fx.today && $0.days == 1 && $0.notes == "framing" && $0.projectId == s.project.id && $0.createdAt == Fx.now })
        XCTAssertThrowsError(try LabourDraft(workDate: Fx.today).makeEntries(companyId: Fx.companyId, projectId: s.project.id, currency: .cad, now: Fx.now)) {
            XCTAssertEqual($0 as? DomainError, .incompleteLabour)
        }
    }

    func testApplyKeepsPersonAndIdentity() throws {
        let s = Lab.Seed()
        let david = s.entries[2]
        var d = LabourDraft(editing: david)
        XCTAssertEqual(d.days, 7)
        XCTAssertEqual(d.lines, [LabourLine(employeeId: david.employeeId, dailyRate: 200)])
        d.days = 8
        let later = Fx.now.addingTimeInterval(60)
        let u = try d.apply(to: david, now: later)
        XCTAssertEqual(u.id, david.id)
        XCTAssertEqual(u.employeeId, david.employeeId)
        XCTAssertEqual(u.cost, Fx.money(1600))
        XCTAssertEqual(u.createdAt, david.createdAt)
        XCTAssertEqual(u.updatedAt, later)
    }

    func testAlreadyLoggedDays() {
        let s = Lab.Seed()
        let entries = s.entries
        let more = Lab.entry(s.project, s.mike, days: "0.5", rate: "250.00", on: "2026-09-23")
        let day = CalendarDate(storage: "2026-09-23")!
        XCTAssertEqual(LabourDraft.alreadyLoggedDays(employeeId: s.mike.id, on: day, entries: entries + [more], excluding: nil), Decimal(string: "8.5"))
        XCTAssertEqual(LabourDraft.alreadyLoggedDays(employeeId: s.mike.id, on: day, entries: entries + [more], excluding: more.id), 8)
        XCTAssertEqual(LabourDraft.alreadyLoggedDays(employeeId: s.john.id, on: Fx.today, entries: entries, excluding: nil), 0)
    }
}
