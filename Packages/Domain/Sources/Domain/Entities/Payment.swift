import Foundation

public struct Payment: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public let projectId: UUID
    /// nil = unallocated: counts toward `collected`, not toward any schedule item.
    public var scheduleItemId: UUID?
    public var amount: Money
    public var paidOn: CalendarDate
    public var method: PaymentMethod
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, projectId: UUID, scheduleItemId: UUID?, amount: Money, paidOn: CalendarDate, method: PaymentMethod, notes: String?, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.projectId = projectId; self.scheduleItemId = scheduleItemId; self.amount = amount
        self.paidOn = paidOn; self.method = method; self.notes = notes; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public func validate() throws {
        if amount.isNegative || amount.isZero { throw DomainError.invalidPaymentAmount }
    }
}
