import Foundation

public struct LabourRow: Hashable, Sendable, Identifiable {
    public let entry: LabourEntry
    /// The person's name, also after they left the crew; "" when the employee row is missing.
    public let employeeName: String
    public let cost: Money
    public var id: UUID { entry.id }
    public init(entry: LabourEntry, employeeName: String, cost: Money) { self.entry = entry; self.employeeName = employeeName; self.cost = cost }
}

public struct LabourDaySection: Hashable, Sendable, Identifiable {
    public let day: CalendarDate
    public let rows: [LabourRow]
    public let total: Money
    public let days: Decimal
    public var id: CalendarDate { day }
    public init(day: CalendarDate, rows: [LabourRow], total: Money, days: Decimal) { self.day = day; self.rows = rows; self.total = total; self.days = days }
}

public struct ProjectLabourList: Hashable, Sendable {
    public let sections: [LabourDaySection]
    public let total: Money
    public let totalDays: Decimal
    public var rows: [LabourRow] { sections.flatMap(\.rows) }
    public init(sections: [LabourDaySection], total: Money, totalDays: Decimal) { self.sections = sections; self.total = total; self.totalDays = totalDays }
}

public enum LabourListComposer {
    /// Spec §3.3: live entries grouped by work date (newest first), by name inside a day; `employees` includes deleted people.
    public static func compose(entries: [LabourEntry], employees: [Employee], currency: CurrencyCode) -> ProjectLabourList {
        let zero = Money.zero(currency)
        let names = Dictionary(employees.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let rows = entries.filter { !$0.isDeleted }.map { LabourRow(entry: $0, employeeName: names[$0.employeeId] ?? "", cost: $0.cost) }
        func sum(_ rows: [LabourRow]) -> Money { (try? Money.sum(rows.map(\.cost), currency: currency)) ?? zero }
        func days(_ rows: [LabourRow]) -> Decimal { rows.reduce(Decimal(0)) { $0 + $1.entry.days } }
        let byDay = Dictionary(grouping: rows, by: { $0.entry.workDate })
        let sections = byDay.keys.sorted(by: >).map { day -> LabourDaySection in
            let dayRows = (byDay[day] ?? []).sorted { a, b in
                let c = a.employeeName.localizedStandardCompare(b.employeeName)
                if c != .orderedSame { return c == .orderedAscending }
                return (a.entry.createdAt, a.id.uuidString) < (b.entry.createdAt, b.id.uuidString)
            }
            return LabourDaySection(day: day, rows: dayRows, total: sum(dayRows), days: days(dayRows))
        }
        return ProjectLabourList(sections: sections, total: sum(rows), totalDays: days(rows))
    }
}
