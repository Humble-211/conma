import Foundation

public struct PaymentScheduleItem: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public let projectId: UUID
    public var label: String
    /// Authoritative payable value. `percentage` is only the generating input.
    public var amount: Money
    public var percentage: Percentage?
    public var dueDate: CalendarDate?
    public var triggerText: String?
    public var isDeposit: Bool
    public var notes: String?
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, projectId: UUID, label: String, amount: Money, percentage: Percentage?, dueDate: CalendarDate?, triggerText: String?, isDeposit: Bool, notes: String?, sortOrder: Int, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.projectId = projectId; self.label = label; self.amount = amount
        self.percentage = percentage; self.dueDate = dueDate; self.triggerText = triggerText; self.isDeposit = isDeposit
        self.notes = notes; self.sortOrder = sortOrder; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public func validate() throws {
        if amount.isNegative { throw DomainError.negativeAmount }
    }
}
