import Foundation

public struct ProjectEstimateLine: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public let projectId: UUID
    public var costGroup: CostGroup
    public var label: String
    public var amount: Money
    public var quantity: Decimal?
    public var unitRate: Money?
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, projectId: UUID, costGroup: CostGroup, label: String, amount: Money, quantity: Decimal?, unitRate: Money?, sortOrder: Int, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.projectId = projectId; self.costGroup = costGroup; self.label = label
        self.amount = amount; self.quantity = quantity; self.unitRate = unitRate; self.sortOrder = sortOrder
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public func validate() throws {
        if amount.isNegative { throw DomainError.negativeAmount }
    }
}
