import Foundation
import GRDB
import Domain

struct PaymentRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "payments"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

    var id: String
    var companyId: String
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?
    var syncState: String
    var projectId: String
    var scheduleItemId: String?
    var amount: String
    var paidOn: String
    var method: String
    var notes: String?

    init(_ p: Payment) {
        id = p.id.dbKey; companyId = p.companyId.dbKey; projectId = p.projectId.dbKey; scheduleItemId = p.scheduleItemId?.dbKey
        createdAt = Timestamps.string(p.createdAt); updatedAt = Timestamps.string(p.updatedAt)
        deletedAt = p.deletedAt.map(Timestamps.string); syncState = SyncState.pending.rawValue
        amount = p.amount.storageString; paidOn = p.paidOn.storageString; method = p.method.rawValue; notes = p.notes
    }

    func toDomain(currency: CurrencyCode) throws -> Payment {
        let t = Self.databaseTableName
        guard let paymentMethod = PaymentMethod(rawValue: method) else { throw DataError.corruptRow(table: t, id: id, column: "method") }
        return Payment(id: try RecordSupport.uuid(id, table: t, id: id, column: "id"),
                       companyId: try RecordSupport.uuid(companyId, table: t, id: id, column: "company_id"),
                       projectId: try RecordSupport.uuid(projectId, table: t, id: id, column: "project_id"),
                       scheduleItemId: try RecordSupport.uuid(scheduleItemId, table: t, id: id, column: "schedule_item_id"),
                       amount: try RecordSupport.money(amount, currency: currency, table: t, id: id, column: "amount"),
                       paidOn: try RecordSupport.requiredCalendarDate(paidOn, table: t, id: id, column: "paid_on"), method: paymentMethod, notes: notes,
                       createdAt: try RecordSupport.date(createdAt, table: t, id: id, column: "created_at"),
                       updatedAt: try RecordSupport.date(updatedAt, table: t, id: id, column: "updated_at"),
                       deletedAt: try RecordSupport.date(deletedAt, table: t, id: id, column: "deleted_at"))
    }

    static func fetchLive(_ db: Database, projectId: String, currency: CurrencyCode) throws -> [Payment] {
        try PaymentRecord.filter(Column("project_id") == projectId && Column("deleted_at") == nil)
            .order(Column("paid_on"), Column.rowID).fetchAll(db).map { try $0.toDomain(currency: currency) }
    }

    static func fetchLive(_ db: Database, companyId: String, currency: CurrencyCode) throws -> [Payment] {
        try PaymentRecord.filter(Column("company_id") == companyId && Column("deleted_at") == nil)
            .order(Column("paid_on"), Column.rowID).fetchAll(db).map { try $0.toDomain(currency: currency) }
    }
}
