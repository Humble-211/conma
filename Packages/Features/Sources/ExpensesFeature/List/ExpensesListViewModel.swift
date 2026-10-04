import Foundation
import Observation
import SwiftUI
import Domain

@Observable
@MainActor
public final class ExpensesListViewModel {
    public private(set) var snapshot: ExpenseListSnapshot?
    public private(set) var list: ExpenseList?
    public private(set) var errorKey: LocalizedStringKey?
    public private(set) var today: CalendarDate
    public var filter: ExpenseFilter { didSet { if filter != oldValue { recompose() } } }
    public let currency: CurrencyCode
    private let companyId: UUID
    private let expenseRepository: any ExpenseRepository
    private var generation = 0

    public init(expenseRepository: any ExpenseRepository, companyId: UUID, currency: CurrencyCode, today: CalendarDate, projectId: UUID? = nil) {
        self.expenseRepository = expenseRepository; self.companyId = companyId; self.currency = currency; self.today = today
        self.filter = ExpenseFilter(projectId: projectId)
    }

    /// Bind to `.task(id:)`; a retry starts a new generation.
    public func start() async {
        generation += 1
        let g = generation
        errorKey = nil
        do {
            for try await value in expenseRepository.observeAll(companyId: companyId) {
                guard g == generation else { return }
                snapshot = value
                recompose()
            }
        } catch is CancellationError {
        } catch { errorKey = "expenses.error" }
    }

    public func retry() { errorKey = nil }

    public func update(today: CalendarDate) {
        guard today != self.today else { return }
        self.today = today
        recompose()
    }

    public var hasAnyExpense: Bool { !(snapshot?.expenses.isEmpty ?? true) }
    public var projectOptions: [Project] { ExpenseProjectChoice.ordered(snapshot?.projects ?? []) }
    /// Categories that occur in the expenses, built-ins in `defaultOrder`, then custom by name.
    public var categoryOptions: [ExpenseCategoryChoice] {
        let used = Set((snapshot?.expenses ?? []).map { ExpenseCategoryChoice($0) })
        let standard = ExpenseCategoryChoice.defaultOrder.map { ExpenseCategoryChoice.standard($0) }.filter { used.contains($0) }
        let custom = (snapshot?.customCategories ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { ExpenseCategoryChoice.custom($0.id) }.filter { used.contains($0) }
        return standard + custom
    }
    public func projectName(_ id: UUID) -> String? { snapshot?.projects.first { $0.id == id }?.name }
    public func customName(_ choice: ExpenseCategoryChoice) -> String? {
        guard case .custom(let id) = choice else { return nil }
        return snapshot?.customCategories.first { $0.id == id }?.name
    }

    private func recompose() {
        if let snapshot { list = ExpenseListComposer.compose(snapshot, filter: filter, today: today) }
    }
}
