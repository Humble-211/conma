import Foundation

/// How the user entered tax: nothing, a money amount, or a percent of the pre-tax amount (spec §2 "Thuế").
public enum TaxInput: Hashable, Sendable {
    case none
    case amount(Decimal)
    case percent(Decimal)
}

public enum ExpenseDraftError: Hashable, Sendable, CaseIterable {
    case projectMissing, amountMissing, amountNotPositive, categoryMissing, taxNegative, taxPercentOutOfRange
}

/// The expense form's state. Pure: no `Date()`, no persistence.
public struct ExpenseDraft: Hashable, Sendable {
    public var projectId: UUID?
    public var amount: Decimal?
    public var category: ExpenseCategoryChoice?
    public var tax: TaxInput
    public var spentOn: CalendarDate
    public var vendorName: String
    public var paymentMethod: PaymentMethod?
    public var notes: String

    public init(projectId: UUID?, spentOn: CalendarDate, defaultTaxPercent: Decimal?) {
        self.projectId = projectId
        self.amount = nil
        self.category = nil
        self.tax = defaultTaxPercent.map(TaxInput.percent) ?? .none
        self.spentOn = spentOn
        self.vendorName = ""
        self.paymentMethod = nil
        self.notes = ""
    }

    public init(editing expense: Expense) {
        projectId = expense.projectId
        amount = expense.amount.amount
        category = ExpenseCategoryChoice(expense)
        tax = expense.tax.isZero ? .none : .amount(expense.tax.amount)
        spentOn = expense.spentOn
        vendorName = expense.vendorName ?? ""
        paymentMethod = expense.paymentMethod
        notes = expense.notes ?? ""
    }

    /// Tax in `currency`; percent mode is ONE rounding of amount × percent. nil when it cannot be computed yet.
    public func taxMoney(currency: CurrencyCode) -> Money? {
        switch tax {
        case .none:
            return .zero(currency)
        case .amount(let value):
            return value < 0 ? nil : Money(value, currency)
        case .percent(let points):
            guard let amount, let percentage = try? Percentage.input(points) else { return nil }
            return Money(amount, currency).multiplied(by: percentage)
        }
    }

    /// amount + tax (what the contractor actually paid).
    public func total(currency: CurrencyCode) -> Money? {
        guard let amount, let tax = taxMoney(currency: currency) else { return nil }
        return try? Money(amount, currency).adding(tax)
    }

    /// In declaration order of `ExpenseDraftError`.
    public var errors: [ExpenseDraftError] {
        var result: [ExpenseDraftError] = []
        if projectId == nil { result.append(.projectMissing) }
        if let amount {
            if Money.rounded(amount) <= 0 { result.append(.amountNotPositive) }
        } else {
            result.append(.amountMissing)
        }
        if category == nil { result.append(.categoryMissing) }
        switch tax {
        case .none: break
        case .amount(let value): if value < 0 { result.append(.taxNegative) }
        case .percent(let points): if (try? Percentage.input(points)) == nil { result.append(.taxPercentOutOfRange) }
        }
        return result
    }

    public var canSave: Bool { errors.isEmpty }

    public func makeExpense(id: UUID, companyId: UUID, currency: CurrencyCode, customCategories: [CustomExpenseCategory], now: Date) throws -> Expense {
        let r = try resolved(currency: currency, customCategories: customCategories)
        return Expense(id: id, companyId: companyId, projectId: r.projectId, category: r.category, customCategoryId: r.customCategoryId,
                       costGroup: r.costGroup, vendorName: Self.clean(vendorName), amount: r.amount, tax: r.tax, spentOn: spentOn,
                       paymentMethod: paymentMethod, notes: Self.clean(notes), receiptImages: [], createdAt: now, updatedAt: now, deletedAt: nil)
    }

    /// Edit: keeps identity, creation time and receipts; re-snapshots the cost group only when the category choice changed.
    public func apply(to existing: Expense, customCategories: [CustomExpenseCategory], now: Date) throws -> Expense {
        let r = try resolved(currency: existing.amount.currency, customCategories: customCategories)
        let group = r.choice == ExpenseCategoryChoice(existing) ? existing.costGroup : r.costGroup
        return Expense(id: existing.id, companyId: existing.companyId, projectId: r.projectId, category: r.category, customCategoryId: r.customCategoryId,
                       costGroup: group, vendorName: Self.clean(vendorName), amount: r.amount, tax: r.tax, spentOn: spentOn,
                       paymentMethod: paymentMethod, notes: Self.clean(notes), receiptImages: existing.receiptImages,
                       createdAt: existing.createdAt, updatedAt: now, deletedAt: existing.deletedAt)
    }

    private struct Resolved {
        let projectId: UUID
        let choice: ExpenseCategoryChoice
        let category: ExpenseCategory
        let customCategoryId: UUID?
        let costGroup: CostGroup
        let amount: Money
        let tax: Money
    }

    private func resolved(currency: CurrencyCode, customCategories: [CustomExpenseCategory]) throws -> Resolved {
        guard errors.isEmpty, let projectId, let amount, let choice = category, let tax = taxMoney(currency: currency) else {
            throw DomainError.incompleteExpense
        }
        switch choice {
        case .standard(let category):
            guard let group = category.defaultCostGroup else { throw DomainError.customCategoryRequired }
            return Resolved(projectId: projectId, choice: choice, category: category, customCategoryId: nil, costGroup: group, amount: Money(amount, currency), tax: tax)
        case .custom(let id):
            guard let custom = customCategories.first(where: { $0.id == id && !$0.isDeleted }) else { throw DomainError.notFound }
            return Resolved(projectId: projectId, choice: choice, category: .custom, customCategoryId: id, costGroup: custom.costGroup, amount: Money(amount, currency), tax: tax)
        }
    }

    static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
