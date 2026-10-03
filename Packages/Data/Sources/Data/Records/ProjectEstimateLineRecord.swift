import Foundation
import GRDB
import Domain

struct ProjectEstimateLineRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "project_estimate_lines"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

    var id: String
    var companyId: String
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?
    var syncState: String
    var projectId: String
    var costGroup: String
    var label: String
    var amount: String
    var quantity: String?
    var unitRate: String?
    var sortOrder: Int

    init(_ l: ProjectEstimateLine) {
        id = l.id.dbKey; companyId = l.companyId.dbKey; projectId = l.projectId.dbKey
        createdAt = Timestamps.string(l.createdAt); updatedAt = Timestamps.string(l.updatedAt)
        deletedAt = l.deletedAt.map(Timestamps.string); syncState = SyncState.pending.rawValue
        costGroup = l.costGroup.rawValue; label = l.label; amount = l.amount.storageString
        quantity = l.quantity.map { "\($0)" }; unitRate = l.unitRate?.storageString; sortOrder = l.sortOrder
    }

    func toDomain(currency: CurrencyCode) throws -> ProjectEstimateLine {
        let t = Self.databaseTableName
        guard let group = CostGroup(rawValue: costGroup) else { throw DataError.corruptRow(table: t, id: id, column: "cost_group") }
        let rate = try unitRate.map { try RecordSupport.money($0, currency: currency, table: t, id: id, column: "unit_rate") }
        return ProjectEstimateLine(id: try RecordSupport.uuid(id, table: t, id: id, column: "id"),
                                   companyId: try RecordSupport.uuid(companyId, table: t, id: id, column: "company_id"),
                                   projectId: try RecordSupport.uuid(projectId, table: t, id: id, column: "project_id"),
                                   costGroup: group, label: label,
                                   amount: try RecordSupport.money(amount, currency: currency, table: t, id: id, column: "amount"),
                                   quantity: try RecordSupport.decimal(quantity, table: t, id: id, column: "quantity"), unitRate: rate, sortOrder: sortOrder,
                                   createdAt: try RecordSupport.date(createdAt, table: t, id: id, column: "created_at"),
                                   updatedAt: try RecordSupport.date(updatedAt, table: t, id: id, column: "updated_at"),
                                   deletedAt: try RecordSupport.date(deletedAt, table: t, id: id, column: "deleted_at"))
    }

    static func fetchLive(_ db: Database, projectId: String, currency: CurrencyCode) throws -> [ProjectEstimateLine] {
        try ProjectEstimateLineRecord.filter(Column("project_id") == projectId && Column("deleted_at") == nil)
            .order(Column("cost_group"), Column("sort_order")).fetchAll(db).map { try $0.toDomain(currency: currency) }
    }

    static func fetchLive(_ db: Database, companyId: String, currency: CurrencyCode) throws -> [ProjectEstimateLine] {
        try ProjectEstimateLineRecord.filter(Column("company_id") == companyId && Column("deleted_at") == nil)
            .order(Column("project_id"), Column("cost_group"), Column("sort_order")).fetchAll(db).map { try $0.toDomain(currency: currency) }
    }
}
