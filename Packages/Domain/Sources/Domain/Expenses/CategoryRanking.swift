import Foundation

public enum CategoryRanking {
    /// How many of the latest live expenses are counted.
    public static let window = 50

    /// Spec §2 "Category nhanh": most used first (ties → more recent use first), then `ExpenseCategoryChoice.defaultOrder`.
    public static func mostUsed(expenses: [Expense], customCategories: [CustomExpenseCategory], limit: Int = 6) -> [ExpenseCategoryChoice] {
        let liveCustom = Set(customCategories.filter { !$0.isDeleted }.map(\.id))
        let recent = expenses.filter { !$0.isDeleted }
            .sorted { ($0.spentOn, $0.createdAt) > ($1.spentOn, $1.createdAt) }
            .prefix(window)
        var counts: [ExpenseCategoryChoice: Int] = [:]
        var firstSeen: [ExpenseCategoryChoice: Int] = [:]   // index in `recent`; smaller = more recent
        for (index, expense) in recent.enumerated() {
            let choice = ExpenseCategoryChoice(expense)
            if case .custom(let id) = choice, !liveCustom.contains(id) { continue }
            counts[choice, default: 0] += 1
            if firstSeen[choice] == nil { firstSeen[choice] = index }
        }
        var result = counts.keys.sorted { a, b in
            let ca = counts[a] ?? 0, cb = counts[b] ?? 0
            if ca != cb { return ca > cb }
            return (firstSeen[a] ?? Int.max) < (firstSeen[b] ?? Int.max)
        }
        for category in ExpenseCategoryChoice.defaultOrder where result.count < limit {
            let choice = ExpenseCategoryChoice.standard(category)
            if !result.contains(choice) { result.append(choice) }
        }
        return Array(result.prefix(limit))
    }
}
