import Foundation

public struct CustomCategoryUsage: Hashable, Sendable, Identifiable {
    public let category: CustomExpenseCategory
    public let liveExpenseCount: Int
    /// true once any expense — even a deleted one — used the category (its group is then locked).
    public let everUsed: Bool
    public var id: UUID { category.id }
    public init(category: CustomExpenseCategory, liveExpenseCount: Int, everUsed: Bool) {
        self.category = category; self.liveExpenseCount = liveExpenseCount; self.everUsed = everUsed
    }
}

public protocol CustomCategoryRepository: Sendable {
    /// Live categories by name (case-insensitive) with usage counts.
    func observeAll(companyId: UUID) -> AsyncThrowingStream<[CustomCategoryUsage], Error>
    /// DomainError.emptyName / .duplicateName.
    func create(_ category: CustomExpenseCategory) async throws
    /// DomainError.notFound / .emptyName / .duplicateName / .categoryInUse.
    func update(id: UUID, name: String, costGroup: CostGroup) async throws
    /// DomainError.notFound / .categoryHasExpenses.
    func softDelete(id: UUID) async throws
}
