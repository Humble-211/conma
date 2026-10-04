import Foundation
import Observation
import SwiftUI
import Domain
import FeatureSupport

public enum ReceiptPage: Identifiable, Equatable {
    case saved(ReceiptImage)
    case new(id: UUID, jpeg: Data)
    public var id: UUID {
        switch self {
        case .saved(let image): return image.id
        case .new(let id, _): return id
        }
    }
}

public enum TaxMode: Hashable { case amount, percent }

@Observable
@MainActor
public final class ExpenseFormViewModel {
    public var draft: ExpenseDraft
    public var taxMode: TaxMode { didSet { syncTax() } }
    public var taxValue: Decimal? { didSet { syncTax() } }
    public private(set) var pages: [ReceiptPage] = []
    public private(set) var snapshot: ExpenseListSnapshot?
    public private(set) var original: Expense?
    public private(set) var isSaving = false
    public private(set) var showErrors = false
    public var alertKey: LocalizedStringKey?
    public var limitNotice = false

    public let request: ExpenseFormRequest
    public let currency: CurrencyCode
    private let companyId: UUID
    private let expenseRepository: any ExpenseRepository
    private let categoryRepository: any CustomCategoryRepository
    private let actor: ActivityActor
    private let defaultTaxPercent: Decimal?
    private var createdCategories: [CustomExpenseCategory] = []
    private var didPickDefaultProject = false

    public init(request: ExpenseFormRequest, companyId: UUID, currency: CurrencyCode, expenseRepository: any ExpenseRepository,
                categoryRepository: any CustomCategoryRepository, actor: ActivityActor, today: CalendarDate, defaultTaxPercent: Decimal?) {
        self.request = request; self.companyId = companyId; self.currency = currency
        self.expenseRepository = expenseRepository; self.categoryRepository = categoryRepository; self.actor = actor
        self.defaultTaxPercent = defaultTaxPercent
        var preset: UUID?
        if case .create(let projectId) = request { preset = projectId }
        let initial = ExpenseDraft(projectId: preset, spentOn: today, defaultTaxPercent: defaultTaxPercent)
        let fields = Self.taxFields(initial.tax)
        draft = initial
        taxMode = fields.mode
        taxValue = fields.value
    }

    public var isEditing: Bool { if case .edit = request { return true } else { return false } }

    /// Bind to `.task`: loads the edited expense once, then keeps projects/categories/ranking live.
    public func start() async {
        if case .edit(let id) = request, original == nil {
            do {
                guard let expense = try await expenseRepository.get(id: id) else { alertKey = "expense.error.gone"; return }
                original = expense
                let edited = ExpenseDraft(editing: expense)
                let fields = Self.taxFields(edited.tax)
                draft = edited
                taxMode = fields.mode
                taxValue = fields.value                      // didSet re-syncs draft.tax from the two fields
                pages = expense.receiptImages.map(ReceiptPage.saved)
            } catch { alertKey = "expense.error.saveFailed" }
        }
        do {
            for try await value in expenseRepository.observeAll(companyId: companyId) {
                snapshot = value
                if !didPickDefaultProject, !isEditing, draft.projectId == nil {
                    draft.projectId = ExpenseProjectChoice.defaultProject(expenses: value.expenses, projects: value.projects)
                }
                didPickDefaultProject = true
            }
        } catch is CancellationError {
        } catch { alertKey = "expenses.error" }
    }

    // MARK: Derived

    public var projects: [Project] { ExpenseProjectChoice.ordered(snapshot?.projects ?? []) }
    public var selectedProjectName: String? { draft.projectId.flatMap { id in snapshot?.projects.first { $0.id == id }?.name } }
    public var liveCustomCategories: [CustomExpenseCategory] {
        let known = snapshot?.customCategories ?? []
        let all = known + createdCategories.filter { c in !known.contains { $0.id == c.id } }
        return all.filter { !$0.isDeleted }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    public func name(for choice: ExpenseCategoryChoice) -> String? {
        guard case .custom(let id) = choice else { return nil }
        return liveCustomCategories.first { $0.id == id }?.name ?? snapshot?.customCategories.first { $0.id == id }?.name
    }
    /// Six chips (spec §2); the current choice is always visible.
    public var quickCategories: [ExpenseCategoryChoice] {
        var chips = CategoryRanking.mostUsed(expenses: snapshot?.expenses ?? [], customCategories: liveCustomCategories)
        if let selected = draft.category, !chips.contains(selected), !chips.isEmpty { chips.removeLast(); chips.insert(selected, at: 0) }
        return chips
    }
    public var taxAmount: Money? { draft.taxMoney(currency: currency) }
    public var total: Money? { draft.total(currency: currency) }
    public var errors: [ExpenseDraftError] { draft.errors }
    public var remainingPages: Int { ReceiptRules.maxPages - pages.count }
    public func fileURL(_ image: ReceiptImage) -> URL { expenseRepository.fileURL(for: image) }

    // MARK: Tax

    public func toggleTaxMode() {
        switch taxMode {
        case .percent:
            let computed = taxAmount?.amount
            taxMode = .amount
            taxValue = computed
        case .amount:
            taxMode = .percent
            taxValue = defaultTaxPercent
        }
    }

    private func syncTax() {
        draft.tax = taxValue.map { taxMode == .percent ? TaxInput.percent($0) : TaxInput.amount($0) } ?? .none
    }

    private static func taxFields(_ tax: TaxInput) -> (mode: TaxMode, value: Decimal?) {
        switch tax {
        case .none: return (.amount, nil)
        case .amount(let value): return (.amount, value)
        case .percent(let points): return (.percent, points)
        }
    }

    // MARK: Pages

    /// Appends pages up to the 10-page limit; sets `limitNotice` when some were dropped.
    public func addPages(_ jpegs: [Data]) {
        let accepted = ReceiptRules.acceptedCount(existing: pages.count, incoming: jpegs.count)
        pages += jpegs.prefix(accepted).map { ReceiptPage.new(id: UUID(), jpeg: $0) }
        if accepted < jpegs.count { limitNotice = true }
    }

    public func removePage(_ id: UUID) { pages.removeAll { $0.id == id } }

    // MARK: Writes

    public func save() async -> Bool {
        showErrors = true
        guard draft.canSave, !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        let categories = (snapshot?.customCategories ?? []) + createdCategories
        let newPages = pages.compactMap { page -> Data? in if case .new(_, let jpeg) = page { return jpeg } else { return nil } }
        do {
            if let original {
                let updated = try draft.apply(to: original, customCategories: categories, now: Date())
                let kept = pages.compactMap { page -> UUID? in if case .saved(let image) = page { return image.id } else { return nil } }
                try await expenseRepository.update(updated, receipts: ReceiptChange(keptImageIds: kept, newPages: newPages), actor: actor)
            } else {
                let expense = try draft.makeExpense(id: UUID(), companyId: companyId, currency: currency, customCategories: categories, now: Date())
                try await expenseRepository.create(expense, receiptPages: newPages, actor: actor)
            }
            return true
        } catch {
            alertKey = Self.key(for: error)
            return false
        }
    }

    public func delete() async -> Bool {
        guard let original else { return false }
        do { try await expenseRepository.softDelete(id: original.id, actor: actor); return true } catch { alertKey = Self.key(for: error); return false }
    }

    /// Creates a custom category from the picker and selects it. Returns an error key, nil on success.
    public func createCategory(name: String, group: CostGroup) async -> LocalizedStringKey? {
        let now = Date()
        let category = CustomExpenseCategory(id: UUID(), companyId: companyId, name: name.trimmingCharacters(in: .whitespacesAndNewlines), costGroup: group,
                                             createdAt: now, updatedAt: now, deletedAt: nil)
        do {
            try await categoryRepository.create(category)
            createdCategories.append(category)
            draft.category = .custom(category.id)
            return nil
        } catch { return CategoriesViewModel.key(for: error) }
    }

    /// Spec §5.2: only these four errors have their own message; everything else is "could not save".
    static func key(for error: Error) -> LocalizedStringKey {
        switch error as? DomainError {
        case .notFound?: return "expense.error.gone"
        case .tooManyReceiptPages?: return "expense.receipt.limit"
        case .currencyMismatch?: return "error.currencyMismatch"
        case .incompleteExpense?: return "expense.error.incomplete"
        default: return "expense.error.saveFailed"
        }
    }
}
