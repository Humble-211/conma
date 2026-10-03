import Foundation
import Domain

public extension CalendarDate {
    /// Noon of this calendar day in `tz` — a stable instant for DatePicker bindings.
    func noonDate(in tz: TimeZone) -> Date {
        var c = DateComponents(); c.year = year; c.month = month; c.day = day; c.hour = 12
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        return cal.date(from: c) ?? Date()
    }
}
