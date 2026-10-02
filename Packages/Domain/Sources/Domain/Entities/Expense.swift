import Foundation

public struct ReceiptImage: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public let expenseId: UUID
    public var filePath: String
    public var remotePath: String?
    public var pageIndex: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, expenseId: UUID, filePath: String, remotePath: String?, pageIndex: Int, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.expenseId = expenseId; self.filePath = filePath; self.remotePath = remotePath
        self.pageIndex = pageIndex; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}

public struct Expense: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public let projectId: UUID
    public var category: ExpenseCategory
    public var customCategoryId: UUID?
    /// Snapshot taken at creation (spec 5.2). Never re-derived later.
    public var costGroup: CostGroup
    public var vendorName: String?
    /// Pre-tax amount.
    public var amount: Money
    public var tax: Money
    public var spentOn: CalendarDate
    public var paymentMethod: PaymentMethod?
    public var notes: String?
    public var receiptImages: [ReceiptImage]
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, projectId: UUID, category: ExpenseCategory, customCategoryId: UUID?, costGroup: CostGroup, vendorName: String?, amount: Money, tax: Money, spentOn: CalendarDate, paymentMethod: PaymentMethod?, notes: String?, receiptImages: [ReceiptImage], createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.projectId = projectId; self.category = category; self.customCategoryId = customCategoryId
        self.costGroup = costGroup; self.vendorName = vendorName; self.amount = amount; self.tax = tax; self.spentOn = spentOn
        self.paymentMethod = paymentMethod; self.notes = notes; self.receiptImages = receiptImages
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    /// The group to snapshot when creating an expense.
    public static func resolveCostGroup(category: ExpenseCategory, customCategory: CustomExpenseCategory?) throws -> CostGroup {
        if let group = category.defaultCostGroup { return group }
        guard let custom = customCategory else { throw DomainError.customCategoryRequired }
        return custom.costGroup
    }

    /// What the contractor actually paid: amount + tax.
    public func totalCost() throws -> Money { try amount.adding(tax) }

    public func validate() throws {
        if amount.isNegative || tax.isNegative { throw DomainError.negativeAmount }
        if category == .custom {
            if customCategoryId == nil { throw DomainError.customCategoryRequired }
        } else if let expected = category.defaultCostGroup, expected != costGroup {
            throw DomainError.costGroupMismatch
        }
    }
}
