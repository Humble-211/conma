import Foundation

/// Everything the expense screens need, from one DB observation.
public struct ExpenseListSnapshot: Hashable, Sendable {
    public var currency: CurrencyCode
    /// Live expenses with their live receipt images ordered by page index.
    public var expenses: [Expense]
    /// Live projects.
    public var projects: [Project]
    /// Every custom category, including deleted ones (names of history rows).
    public var customCategories: [CustomExpenseCategory]

    public init(currency: CurrencyCode, expenses: [Expense], projects: [Project], customCategories: [CustomExpenseCategory]) {
        self.currency = currency; self.expenses = expenses; self.projects = projects; self.customCategories = customCategories
    }
}

public struct ExpenseFilter: Hashable, Sendable {
    public var projectId: UUID?
    public var category: ExpenseCategoryChoice?
    public var query: String
    public init(projectId: UUID? = nil, category: ExpenseCategoryChoice? = nil, query: String = "") {
        self.projectId = projectId; self.category = category; self.query = query
    }
}

public struct ExpenseRow: Hashable, Sendable, Identifiable {
    public let expense: Expense
    public let choice: ExpenseCategoryChoice
    public let customCategoryName: String?
    public let projectName: String
    public let total: Money
    public var receiptCount: Int { expense.receiptImages.filter { !$0.isDeleted }.count }
    public var id: UUID { expense.id }
    public init(expense: Expense, choice: ExpenseCategoryChoice, customCategoryName: String?, projectName: String, total: Money) {
        self.expense = expense; self.choice = choice; self.customCategoryName = customCategoryName; self.projectName = projectName; self.total = total
    }
}

public struct ExpenseDaySection: Hashable, Sendable, Identifiable {
    public let day: CalendarDate
    public let rows: [ExpenseRow]
    public let total: Money
    public var id: CalendarDate { day }
    public init(day: CalendarDate, rows: [ExpenseRow], total: Money) { self.day = day; self.rows = rows; self.total = total }
}

public struct ExpenseList: Hashable, Sendable {
    public let sections: [ExpenseDaySection]
    public let thisMonth: Money
    public let lastMonth: Money
    public var rows: [ExpenseRow] { sections.flatMap(\.rows) }
    public init(sections: [ExpenseDaySection], thisMonth: Money, lastMonth: Money) { self.sections = sections; self.thisMonth = thisMonth; self.lastMonth = lastMonth }
}

public enum ExpenseListComposer {
    /// Spec §2 "Tab Chi phí": day sections newest first; month totals honour the project/category filter but not the search text.
    public static func compose(_ snapshot: ExpenseListSnapshot, filter: ExpenseFilter, today: CalendarDate) -> ExpenseList {
        let currency = snapshot.currency
        let zero = Money.zero(currency)
        let projectNames = Dictionary(snapshot.projects.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let customNames = Dictionary(snapshot.customCategories.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        func sum(_ rows: [ExpenseRow]) -> Money { (try? Money.sum(rows.map(\.total), currency: currency)) ?? zero }

        let scoped = snapshot.expenses.filter { e in
            !e.isDeleted
                && (filter.projectId == nil || e.projectId == filter.projectId)
                && (filter.category == nil || ExpenseCategoryChoice(e) == filter.category)
        }
        let rows = scoped.map { e -> ExpenseRow in
            let choice = ExpenseCategoryChoice(e)
            var customName: String?
            if case .custom(let id) = choice { customName = customNames[id] }
            return ExpenseRow(expense: e, choice: choice, customCategoryName: customName, projectName: projectNames[e.projectId] ?? "",
                              total: (try? e.totalCost()) ?? zero)
        }

        let previous = today.month == 1 ? (year: today.year - 1, month: 12) : (year: today.year, month: today.month - 1)
        let thisMonth = sum(rows.filter { $0.expense.spentOn.year == today.year && $0.expense.spentOn.month == today.month })
        let lastMonth = sum(rows.filter { $0.expense.spentOn.year == previous.year && $0.expense.spentOn.month == previous.month })

        let needle = SearchFold.normalize(filter.query)
        let visible = needle.isEmpty ? rows : rows.filter { row in
            [row.expense.vendorName, row.expense.notes].compactMap { $0 }.contains { SearchFold.normalize($0).contains(needle) }
        }
        let byDay = Dictionary(grouping: visible, by: { $0.expense.spentOn })
        let sections = byDay.keys.sorted(by: >).map { day -> ExpenseDaySection in
            let dayRows = (byDay[day] ?? []).sorted { ($0.expense.createdAt, $0.id.uuidString) > ($1.expense.createdAt, $1.id.uuidString) }
            return ExpenseDaySection(day: day, rows: dayRows, total: sum(dayRows))
        }
        return ExpenseList(sections: sections, thisMonth: thisMonth, lastMonth: lastMonth)
    }
}
