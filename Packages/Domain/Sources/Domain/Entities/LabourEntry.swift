import Foundation

public struct LabourEntry: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public let projectId: UUID
    public let employeeId: UUID
    public var workDate: CalendarDate
    /// e.g. 0.5 for half a day. Must be > 0.
    public var days: Decimal
    /// Snapshot of the employee's rate at entry time.
    public var dailyRate: Money
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, projectId: UUID, employeeId: UUID, workDate: CalendarDate, days: Decimal, dailyRate: Money, notes: String?, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.projectId = projectId; self.employeeId = employeeId; self.workDate = workDate
        self.days = days; self.dailyRate = dailyRate; self.notes = notes; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public static func cost(days: Decimal, dailyRate: Money) -> Money { dailyRate.multiplied(by: days) }
    public var cost: Money { LabourEntry.cost(days: days, dailyRate: dailyRate) }

    public func validate() throws {
        if days <= 0 { throw DomainError.invalidLabourDays }
        if dailyRate.isNegative { throw DomainError.negativeAmount }
    }
}
