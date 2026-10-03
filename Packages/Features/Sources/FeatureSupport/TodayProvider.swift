import Foundation
import Domain

public enum TodayProvider {
    /// App-wide "today"; UI tests override it via `--today` (set once by the App target at launch).
    nonisolated(unsafe) public static var override: CalendarDate?

    public static func today(timeZone: TimeZone) -> CalendarDate {
        override ?? CalendarDate(Date(), timeZone: timeZone)
    }
}
