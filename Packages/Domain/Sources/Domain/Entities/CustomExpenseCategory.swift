import Foundation

public struct CustomExpenseCategory: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public var name: String
    /// Immutable once any expense (even a deleted one) uses this category.
    public var costGroup: CostGroup
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, name: String, costGroup: CostGroup, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.name = name; self.costGroup = costGroup
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public func validate() throws {
        if name.isBlank { throw DomainError.emptyName }
    }
}
