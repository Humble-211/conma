import XCTest
@testable import Domain

final class CalendarDateTests: XCTestCase {
    func testStorageRoundTrip() {
        let d = CalendarDate(storage: "2026-10-05")
        XCTAssertEqual(d?.year, 2026); XCTAssertEqual(d?.month, 10); XCTAssertEqual(d?.day, 5)
        XCTAssertEqual(d?.storageString, "2026-10-05")
        XCTAssertEqual(CalendarDate(year: 2026, month: 1, day: 9)?.storageString, "2026-01-09")
    }

    func testRejectsInvalidDates() {
        XCTAssertNil(CalendarDate(storage: "2026-02-30"))
        XCTAssertNil(CalendarDate(storage: "2026-2-3"))
        XCTAssertNil(CalendarDate(storage: "2026/02/03"))
        XCTAssertNil(CalendarDate(storage: "2026-13-01"))
        XCTAssertNil(CalendarDate(year: 2025, month: 2, day: 29))
        XCTAssertNotNil(CalendarDate(year: 2024, month: 2, day: 29))
    }

    func testDaysUntilAcrossLeapDayAndYears() {
        let a = CalendarDate(storage: "2024-02-28")!, b = CalendarDate(storage: "2024-03-01")!
        XCTAssertEqual(a.daysUntil(b), 2)
        XCTAssertEqual(b.daysUntil(a), -2)
        XCTAssertEqual(a.daysUntil(a), 0)
        XCTAssertEqual(CalendarDate(storage: "2025-12-31")!.daysUntil(CalendarDate(storage: "2026-01-01")!), 1)
    }

    func testDaysUntilAcrossDSTChangeIsWholeDays() {
        // Toronto DST starts 2026-03-08; calendar math must not produce 23-hour days.
        let a = CalendarDate(storage: "2026-03-07")!, b = CalendarDate(storage: "2026-03-09")!
        XCTAssertEqual(a.daysUntil(b), 2)
    }

    func testAddingDays() {
        XCTAssertEqual(CalendarDate(storage: "2026-10-30")!.adding(days: 3).storageString, "2026-11-02")
        XCTAssertEqual(CalendarDate(storage: "2026-01-01")!.adding(days: -1).storageString, "2025-12-31")
    }

    func testComparable() {
        XCTAssertLessThan(CalendarDate(storage: "2026-01-31")!, CalendarDate(storage: "2026-02-01")!)
    }

    func testFromDateUsesGivenTimeZone() {
        // 2026-10-05 03:30 UTC is still 2026-10-04 in Toronto (UTC-4).
        let instant = Date(timeIntervalSince1970: 1_791_171_000) // 2026-10-05T03:30:00Z
        XCTAssertEqual(CalendarDate(instant, timeZone: TimeZone(identifier: "UTC")!).storageString, "2026-10-05")
        XCTAssertEqual(CalendarDate(instant, timeZone: TimeZone(identifier: "America/Toronto")!).storageString, "2026-10-04")
    }
}
