import Foundation
import GRDB
import Domain

struct ExpenseRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "expenses"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

    var id: String
    var companyId: String
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?
    var syncState: String
    var projectId: String
    var category: String
    var customCategoryId: String?
    var costGroup: String
    var vendorName: String?
    var amount: String
    var tax: String
    var spentOn: String
    var paymentMethod: String?
    var notes: String?

    init(_ e: Expense) {
        id = e.id.dbKey; companyId = e.companyId.dbKey; projectId = e.projectId.dbKey
        createdAt = Timestamps.string(e.createdAt); updatedAt = Timestamps.string(e.updatedAt)
        deletedAt = e.deletedAt.map(Timestamps.string); syncState = SyncState.pending.rawValue
        category = e.category.rawValue; customCategoryId = e.customCategoryId?.dbKey; costGroup = e.costGroup.rawValue; vendorName = e.vendorName
        amount = e.amount.storageString; tax = e.tax.storageString; spentOn = e.spentOn.storageString
        paymentMethod = e.paymentMethod?.rawValue; notes = e.notes
    }

    func toDomain(currency: CurrencyCode, receipts: [ReceiptImage] = []) throws -> Expense {
        let t = Self.databaseTableName
        guard let cat = ExpenseCategory(rawValue: category) else { throw DataError.corruptRow(table: t, id: id, column: "category") }
        guard let group = CostGroup(rawValue: costGroup) else { throw DataError.corruptRow(table: t, id: id, column: "cost_group") }
        let method = try paymentMethod.map { raw -> PaymentMethod in
            guard let m = PaymentMethod(rawValue: raw) else { throw DataError.corruptRow(table: t, id: id, column: "payment_method") }
            return m
        }
        return Expense(id: try RecordSupport.uuid(id, table: t, id: id, column: "id"),
                       companyId: try RecordSupport.uuid(companyId, table: t, id: id, column: "company_id"),
                       projectId: try RecordSupport.uuid(projectId, table: t, id: id, column: "project_id"), category: cat,
                       customCategoryId: try RecordSupport.uuid(customCategoryId, table: t, id: id, column: "custom_category_id"), costGroup: group, vendorName: vendorName,
                       amount: try RecordSupport.money(amount, currency: currency, table: t, id: id, column: "amount"),
                       tax: try RecordSupport.money(tax, currency: currency, table: t, id: id, column: "tax"),
                       spentOn: try RecordSupport.requiredCalendarDate(spentOn, table: t, id: id, column: "spent_on"),
                       paymentMethod: method, notes: notes, receiptImages: receipts,
                       createdAt: try RecordSupport.date(createdAt, table: t, id: id, column: "created_at"),
                       updatedAt: try RecordSupport.date(updatedAt, table: t, id: id, column: "updated_at"),
                       deletedAt: try RecordSupport.date(deletedAt, table: t, id: id, column: "deleted_at"))
    }

    static func fetchLive(_ db: Database, projectId: String, currency: CurrencyCode) throws -> [Expense] {
        try ExpenseRecord.filter(Column("project_id") == projectId && Column("deleted_at") == nil)
            .order(Column("spent_on"), Column.rowID).fetchAll(db).map { try $0.toDomain(currency: currency) }
    }

    static func fetchLive(_ db: Database, companyId: String, currency: CurrencyCode) throws -> [Expense] {
        try ExpenseRecord.filter(Column("company_id") == companyId && Column("deleted_at") == nil)
            .order(Column("spent_on"), Column.rowID).fetchAll(db).map { try $0.toDomain(currency: currency) }
    }
}
