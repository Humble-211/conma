// Packages/Data/Sources/Data/Records/CustomExpenseCategoryRecord.swift
import Foundation
import GRDB
import Domain

struct CustomExpenseCategoryRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "custom_expense_categories"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

    var id: String
    var companyId: String
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?
    var syncState: String
    var name: String
    var costGroup: String

    init(_ c: CustomExpenseCategory) {
        id = c.id.dbKey; companyId = c.companyId.dbKey
        createdAt = Timestamps.string(c.createdAt); updatedAt = Timestamps.string(c.updatedAt)
        deletedAt = c.deletedAt.map(Timestamps.string); syncState = SyncState.pending.rawValue
        name = c.name; costGroup = c.costGroup.rawValue
    }

    func toDomain() throws -> CustomExpenseCategory {
        let t = Self.databaseTableName
        guard let group = CostGroup(rawValue: costGroup) else { throw DataError.corruptRow(table: t, id: id, column: "cost_group") }
        return CustomExpenseCategory(id: try RecordSupport.uuid(id, table: t, id: id, column: "id"),
                                     companyId: try RecordSupport.uuid(companyId, table: t, id: id, column: "company_id"),
                                     name: name, costGroup: group,
                                     createdAt: try RecordSupport.date(createdAt, table: t, id: id, column: "created_at"),
                                     updatedAt: try RecordSupport.date(updatedAt, table: t, id: id, column: "updated_at"),
                                     deletedAt: try RecordSupport.date(deletedAt, table: t, id: id, column: "deleted_at"))
    }
}
