import XCTest
@testable import Domain

final class LabourListTests: XCTestCase {
    func testSeedSectionsNewestFirst() {
        let s = Lab.Seed()
        let l = LabourListComposer.compose(entries: s.entries, employees: [s.mike, s.john, s.david], currency: .cad)
        XCTAssertEqual(l.sections.map(\.day.storageString), ["2026-09-25", "2026-09-24", "2026-09-23"])
        XCTAssertEqual(l.sections.map(\.total.storageString), ["1400.00", "2200.00", "2000.00"])
        XCTAssertEqual(l.rows.map(\.employeeName), ["David", "John", "Mike"])
        XCTAssertEqual(l.total, Fx.money(5600))
        XCTAssertEqual(l.totalDays, 25)
    }

    func testSameDaySortedByNameAndDeletedHandling() {
        let s = Lab.Seed()
        var gone = s.john
        gone.deletedAt = Fx.now                                                   // left the crew: the name stays on history
        let today = [Lab.entry(s.project, s.mike, days: "1", rate: "250.00", on: "2026-10-03"),
                     Lab.entry(s.project, gone, days: "0.5", rate: "220.00", on: "2026-10-03"),
                     Lab.entry(s.project, s.david, days: "1", rate: "200.00", on: "2026-10-03", deletedAt: Fx.now)]
        let stranger = Lab.entry(s.project, Lab.employee("X", rate: "1.00"), days: "1", rate: "100.00", on: "2026-10-02")
        let l = LabourListComposer.compose(entries: today + [stranger], employees: [s.mike, gone, s.david], currency: .cad)
        XCTAssertEqual(l.sections.first?.rows.map(\.employeeName), ["John", "Mike"])
        XCTAssertEqual(l.sections.first?.total, Fx.money(360))
        XCTAssertEqual(l.sections.first?.days, Decimal(string: "1.5"))
        XCTAssertEqual(l.sections.last?.rows.first?.employeeName, "")
        XCTAssertEqual(l.total, Fx.money(460))
    }

    func testEmpty() {
        let l = LabourListComposer.compose(entries: [], employees: [], currency: .cad)
        XCTAssertTrue(l.sections.isEmpty)
        XCTAssertEqual(l.total, Fx.money(0))
        XCTAssertEqual(l.totalDays, 0)
    }
}
