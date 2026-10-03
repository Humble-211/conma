import Foundation

public enum TimelineError: Hashable, Sendable, CaseIterable { case completionBeforeStart, hoursPerDayOutOfRange, workingDaysNegative, workersPerDayNegative }

public enum TimelineValidator {
    public static func validate(start: CalendarDate?, completion: CalendarDate?, workingDays: Int?, hoursPerDay: Decimal?, workersPerDay: Int?) -> [TimelineError] {
        var errors: [TimelineError] = []
        if let s = start, let e = completion, e < s { errors.append(.completionBeforeStart) }
        if let h = hoursPerDay, !(h > 0 && h <= 24) { errors.append(.hoursPerDayOutOfRange) }
        if let w = workingDays, w < 0 { errors.append(.workingDaysNegative) }
        if let w = workersPerDay, w < 0 { errors.append(.workersPerDayNegative) }
        return errors
    }
}
