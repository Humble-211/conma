import XCTest
@testable import Domain

final class TimelineValidatorTests: XCTestCase {
    let d0 = CalendarDate(storage: "2026-10-03")!, d1 = CalendarDate(storage: "2026-10-04")!
    func testValid() { XCTAssertEqual(TimelineValidator.validate(start: d0, completion: d1, workingDays: 5, hoursPerDay: 24, workersPerDay: 0), []) }
    func testNilsAreValid() { XCTAssertEqual(TimelineValidator.validate(start: nil, completion: nil, workingDays: nil, hoursPerDay: nil, workersPerDay: nil), []) }
    func testSameDayValid() { XCTAssertEqual(TimelineValidator.validate(start: d0, completion: d0, workingDays: nil, hoursPerDay: nil, workersPerDay: nil), []) }
    func testEachError() {
        XCTAssertEqual(TimelineValidator.validate(start: d1, completion: d0, workingDays: nil, hoursPerDay: nil, workersPerDay: nil), [.completionBeforeStart])
        XCTAssertEqual(TimelineValidator.validate(start: nil, completion: nil, workingDays: nil, hoursPerDay: 0, workersPerDay: nil), [.hoursPerDayOutOfRange])
        XCTAssertEqual(TimelineValidator.validate(start: nil, completion: nil, workingDays: nil, hoursPerDay: Decimal(string: "24.5"), workersPerDay: nil), [.hoursPerDayOutOfRange])
        XCTAssertEqual(TimelineValidator.validate(start: nil, completion: nil, workingDays: -1, hoursPerDay: nil, workersPerDay: nil), [.workingDaysNegative])
        XCTAssertEqual(TimelineValidator.validate(start: nil, completion: nil, workingDays: nil, hoursPerDay: nil, workersPerDay: -3), [.workersPerDayNegative])
    }
    func testCombinedOrder() {
        XCTAssertEqual(TimelineValidator.validate(start: d1, completion: d0, workingDays: -1, hoursPerDay: 30, workersPerDay: -1),
                       [.completionBeforeStart, .hoursPerDayOutOfRange, .workingDaysNegative, .workersPerDayNegative])
    }
    func testAssemblerReportsTimelineErrors() {
        var draft = ProjectDraft(); draft.jobType = .kitchen; draft.customer = .existing(UUID()); draft.address = Address(line: "1 A", unit: nil, city: nil, region: nil, postalCode: nil)
        draft.contractValue = Money(1000, .cad); draft.hoursPerDay = 30; draft.workingDays = -2
        XCTAssertThrowsError(try ProjectDraftAssembler.assemble(draft, companyId: UUID(), currency: .cad, now: Fx.now)) { error in
            XCTAssertEqual(error as? DraftError, .invalidTimeline([.hoursPerDayOutOfRange, .workingDaysNegative]))
        }
    }
}
