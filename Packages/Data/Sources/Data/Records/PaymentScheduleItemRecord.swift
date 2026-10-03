import Foundation
import GRDB
import Domain

struct PaymentScheduleItemRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "payment_schedule_items"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

    var id: String
    var companyId: String
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?
    var syncState: String
    var projectId: String
    var label: String
    var amount: String
    var percentage: String?
    var dueDate: String?
    var triggerText: String?
    var isDeposit: Bool
    var notes: String?
    var sortOrder: Int

    init(_ i: PaymentScheduleItem) {
        id = i.id.dbKey; companyId = i.companyId.dbKey; projectId = i.projectId.dbKey
        createdAt = Timestamps.string(i.createdAt); updatedAt = Timestamps.string(i.updatedAt)
        deletedAt = i.deletedAt.map(Timestamps.string); syncState = SyncState.pending.rawValue
        label = i.label; amount = i.amount.storageString; percentage = i.percentage.map { "\($0.points)" }
        dueDate = i.dueDate?.storageString; triggerText = i.triggerText; isDeposit = i.isDeposit; notes = i.notes; sortOrder = i.sortOrder
    }

    func toDomain(currency: CurrencyCode) throws -> PaymentScheduleItem {
        let t = Self.databaseTableName
        let pct = try RecordSupport.decimal(percentage, table: t, id: id, column: "percentage").map { Percentage.exact($0) }
        return PaymentScheduleItem(id: try RecordSupport.uuid(id, table: t, id: id, column: "id"),
                                   companyId: try RecordSupport.uuid(companyId, table: t, id: id, column: "company_id"),
                                   projectId: try RecordSupport.uuid(projectId, table: t, id: id, column: "project_id"),
                                   label: label, amount: try RecordSupport.money(amount, currency: currency, table: t, id: id, column: "amount"),
                                   percentage: pct, dueDate: try RecordSupport.calendarDate(dueDate, table: t, id: id, column: "due_date"),
                                   triggerText: triggerText, isDeposit: isDeposit, notes: notes, sortOrder: sortOrder,
                                   createdAt: try RecordSupport.date(createdAt, table: t, id: id, column: "created_at"),
                                   updatedAt: try RecordSupport.date(updatedAt, table: t, id: id, column: "updated_at"),
                                   deletedAt: try RecordSupport.date(deletedAt, table: t, id: id, column: "deleted_at"))
    }

    static func fetchLive(_ db: Database, projectId: String, currency: CurrencyCode) throws -> [PaymentScheduleItem] {
        try PaymentScheduleItemRecord.filter(Column("project_id") == projectId && Column("deleted_at") == nil)
            .order(Column("sort_order")).fetchAll(db).map { try $0.toDomain(currency: currency) }
    }
}
