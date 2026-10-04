import Foundation

/// What the user picked: a built-in category (never `.custom`) or one of their custom categories.
public enum ExpenseCategoryChoice: Hashable, Sendable {
    case standard(ExpenseCategory)
    case custom(UUID)

    public init(_ expense: Expense) {
        if expense.category == .custom {
            if let id = expense.customCategoryId { self = .custom(id) } else { self = .standard(.other) }
        } else {
            self = .standard(expense.category)
        }
    }

    /// Quick-chip fallback order (spec §2): what a renovation contractor buys most often first. All 13 built-ins.
    public static let defaultOrder: [ExpenseCategory] = [.materials, .fuel, .toolPurchase, .equipmentRental, .subcontractor, .delivery,
                                                         .wasteDisposal, .permit, .inspection, .parking, .labour, .office, .other]
}
