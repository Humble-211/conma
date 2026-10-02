import Foundation
import GRDB
import Domain

struct ProjectScopeFieldRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "project_scope_fields"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

    var id: String
    var companyId: String
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?
    var syncState: String
    var projectId: String
    var fieldKey: String
    var valueText: String
    var sortOrder: Int

    init(_ f: ProjectScopeField) {
        id = f.id.dbKey; companyId = f.companyId.dbKey; projectId = f.projectId.dbKey
        createdAt = Timestamps.string(f.createdAt); updatedAt = Timestamps.string(f.updatedAt)
        deletedAt = f.deletedAt.map(Timestamps.string); syncState = SyncState.pending.rawValue
        fieldKey = f.fieldKey; valueText = f.valueText; sortOrder = f.sortOrder
    }

    func toDomain() throws -> ProjectScopeField {
        let t = Self.databaseTableName
        return ProjectScopeField(id: try RecordSupport.uuid(id, table: t, id: id, column: "id"),
                                 companyId: try RecordSupport.uuid(companyId, table: t, id: id, column: "company_id"),
                                 projectId: try RecordSupport.uuid(projectId, table: t, id: id, column: "project_id"),
                                 fieldKey: fieldKey, valueText: valueText, sortOrder: sortOrder,
                                 createdAt: try RecordSupport.date(createdAt, table: t, id: id, column: "created_at"),
                                 updatedAt: try RecordSupport.date(updatedAt, table: t, id: id, column: "updated_at"),
                                 deletedAt: try RecordSupport.date(deletedAt, table: t, id: id, column: "deleted_at"))
    }
}
