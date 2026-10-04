import Foundation

/// Foundation §5.2 / A.2 rules for user categories; the repository runs them inside its transaction.
public enum CustomCategoryRules {
    /// Trimmed, non-empty, unique among live categories (case/diacritic-insensitive via `SearchFold`).
    public static func validatedName(_ name: String, excluding id: UUID?, existing: [CustomExpenseCategory]) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DomainError.emptyName }
        let folded = SearchFold.normalize(trimmed)
        if existing.contains(where: { !$0.isDeleted && $0.id != id && SearchFold.normalize($0.name) == folded }) { throw DomainError.duplicateName }
        return trimmed
    }

    /// Rename is always allowed; a group change is refused once any expense (even a deleted one) used the category.
    public static func update(_ category: CustomExpenseCategory, name: String, costGroup: CostGroup, everUsed: Bool, existing: [CustomExpenseCategory]) throws -> CustomExpenseCategory {
        var updated = category
        updated.name = try validatedName(name, excluding: category.id, existing: existing)
        if costGroup != category.costGroup {
            guard !everUsed else { throw DomainError.categoryInUse }
            updated.costGroup = costGroup
        }
        return updated
    }

    public static func checkDelete(liveExpenseCount: Int) throws {
        if liveExpenseCount > 0 { throw DomainError.categoryHasExpenses }
    }
}

public enum ReceiptRules {
    public static let maxPages = 10

    public static func validate(pageCount: Int) throws {
        if pageCount > maxPages { throw DomainError.tooManyReceiptPages }
    }

    /// How many of `incoming` pages fit next to `existing` ones.
    public static func acceptedCount(existing: Int, incoming: Int) -> Int {
        max(0, min(incoming, maxPages - existing))
    }
}
