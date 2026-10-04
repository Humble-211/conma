import Foundation
import Observation
import SwiftUI
import Domain

@Observable
@MainActor
public final class CategoriesViewModel {
    public private(set) var categories: [CustomCategoryUsage] = []
    public var alertKey: LocalizedStringKey?
    private let repository: any CustomCategoryRepository
    private let companyId: UUID

    public init(categoryRepository: any CustomCategoryRepository, companyId: UUID) { self.repository = categoryRepository; self.companyId = companyId }

    public func start() async {
        do { for try await value in repository.observeAll(companyId: companyId) { categories = value } }
        catch is CancellationError {} catch { alertKey = "error.generic" }
    }

    public func create(name: String, group: CostGroup) async -> LocalizedStringKey? {
        let now = Date()
        let category = CustomExpenseCategory(id: UUID(), companyId: companyId, name: name, costGroup: group, createdAt: now, updatedAt: now, deletedAt: nil)
        return await run { try await self.repository.create(category) }
    }
    public func update(_ id: UUID, name: String, group: CostGroup) async -> LocalizedStringKey? { await run { try await self.repository.update(id: id, name: name, costGroup: group) } }
    public func delete(_ id: UUID) async -> LocalizedStringKey? { await run { try await self.repository.softDelete(id: id) } }

    private func run(_ work: () async throws -> Void) async -> LocalizedStringKey? {
        do { try await work(); return nil } catch { return Self.key(for: error) }
    }

    public static func key(for error: Error) -> LocalizedStringKey {
        switch error as? DomainError {
        case .emptyName?: return "categories.error.emptyName"
        case .duplicateName?: return "categories.error.duplicateName"
        case .categoryInUse?: return "categories.error.categoryInUse"
        case .categoryHasExpenses?: return "categories.error.categoryHasExpenses"
        case .notFound?: return "expense.error.gone"
        default: return "error.generic"
        }
    }
}
