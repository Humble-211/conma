import Foundation

public struct Clock: Sendable {
    public var now: @Sendable () -> Date
    public var timeZone: TimeZone

    public init(now: @escaping @Sendable () -> Date, timeZone: TimeZone) {
        self.now = now; self.timeZone = timeZone
    }

    public static let system = Clock(now: { Date() }, timeZone: .current)
    public static func fixed(_ date: Date, timeZone: TimeZone = .gmt) -> Clock {
        Clock(now: { date }, timeZone: timeZone)
    }
}
