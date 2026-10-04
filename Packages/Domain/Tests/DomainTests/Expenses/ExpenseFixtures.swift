import Foundation
@testable import Domain

enum Ex {
    static let basement = Fx.project("Basement Renovation", customer: Fx.customer("Ann Lee"), status: .inProgress, contract: 38_000, progress: 65, start: -18, end: 27)
    static let kitchen = Fx.project("Kitchen Renovation", customer: Fx.customer("David Nguyen"), status: .awaitingDeposit, contract: 25_000, progress: nil, start: 0, end: 34)
    static let roof = Fx.project("Roof Replacement", customer: Fx.customer("Maria Santos"), status: .completed, contract: 18_500, progress: 100, start: -63, end: -44)

    static func expense(_ project: Project, _ category: ExpenseCategory, amount: String, tax: String, on day: String, vendor: String? = nil, notes: String? = nil,
                        custom: UUID? = nil, createdAt: Date = Fx.now, receipts: Int = 0, deletedAt: Date? = nil) -> Expense {
        let id = UUID()
        let images = (0..<receipts).map {
            ReceiptImage(id: UUID(), companyId: Fx.companyId, expenseId: id, filePath: "Receipts/\(id)/\($0).jpg", remotePath: nil, pageIndex: $0,
                         createdAt: Fx.now, updatedAt: Fx.now, deletedAt: nil)
        }
        return Expense(id: id, companyId: Fx.companyId, projectId: project.id, category: category, customCategoryId: custom,
                       costGroup: category.defaultCostGroup ?? .other, vendorName: vendor, amount: Fx.moneyS(amount), tax: Fx.moneyS(tax),
                       spentOn: CalendarDate(storage: day)!, paymentMethod: .creditCard, notes: notes, receiptImages: images,
                       createdAt: createdAt, updatedAt: createdAt, deletedAt: deletedAt)
    }

    /// Spec §4 seed expenses (today = 2026-10-03): Lumber, Dumpster, Drywall — all Basement.
    static func seed() -> [Expense] {
        [expense(basement, .materials, amount: "2400.00", tax: "312.00", on: "2026-09-18", vendor: "Lumber — Home Depot", receipts: 2),
         expense(basement, .wasteDisposal, amount: "600.00", tax: "78.00", on: "2026-09-17", vendor: "Dumpster rental", receipts: 1),
         expense(basement, .materials, amount: "1500.00", tax: "195.00", on: "2026-10-01", vendor: "Drywall")]
    }

    static func custom(_ name: String, _ group: CostGroup, deleted: Bool = false) -> CustomExpenseCategory {
        CustomExpenseCategory(id: UUID(), companyId: Fx.companyId, name: name, costGroup: group, createdAt: Fx.now, updatedAt: Fx.now, deletedAt: deleted ? Fx.now : nil)
    }
}
