import Foundation

/// A calendar day without time: due dates, start dates, completion dates.
public struct CalendarDate: Hashable, Comparable, Sendable, Codable {
    public let year: Int
    public let month: Int
    public let day: Int

    private static let utc = TimeZone.gmt
    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utc
        return c
    }

    public init?(year: Int, month: Int, day: Int) {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        guard components.isValidDate(in: CalendarDate.calendar) else { return nil }
        self.year = year; self.month = month; self.day = day
    }

    /// Parses exactly `YYYY-MM-DD`.
    public init?(storage: String) {
        let parts = storage.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// The calendar day of an instant, as seen in `timeZone`.
    public init(_ date: Date, timeZone: TimeZone) {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        let parts = c.dateComponents([.year, .month, .day], from: date)
        self.year = parts.year ?? 1970; self.month = parts.month ?? 1; self.day = parts.day ?? 1
    }

    public var storageString: String {
        func pad(_ v: Int, _ width: Int) -> String {
            let s = String(v)
            return String(repeating: "0", count: max(0, width - s.count)) + s
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }

    private var midnightUTC: Date {
        var c = DateComponents(); c.year = year; c.month = month; c.day = day
        return CalendarDate.calendar.date(from: c) ?? Date(timeIntervalSince1970: 0)
    }

    /// Whole calendar days from `self` to `other`; negative when `other` is earlier.
    public func daysUntil(_ other: CalendarDate) -> Int {
        CalendarDate.calendar.dateComponents([.day], from: midnightUTC, to: other.midnightUTC).day ?? 0
    }

    public func adding(days: Int) -> CalendarDate {
        let shifted = CalendarDate.calendar.date(byAdding: .day, value: days, to: midnightUTC) ?? midnightUTC
        return CalendarDate(shifted, timeZone: CalendarDate.utc)
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
