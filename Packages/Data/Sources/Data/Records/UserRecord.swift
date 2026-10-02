import Foundation
import GRDB
import Domain

struct UserRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "users"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

    var id: String
    var companyId: String
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?
    var syncState: String
    var displayName: String
    var email: String?
    var role: String
    var authUserId: String?

    init(_ user: User) {
        id = user.id.dbKey; companyId = user.companyId.dbKey
        createdAt = Timestamps.string(user.createdAt); updatedAt = Timestamps.string(user.updatedAt)
        deletedAt = user.deletedAt.map(Timestamps.string); syncState = SyncState.pending.rawValue
        displayName = user.displayName; email = user.email; role = user.role.rawValue; authUserId = user.authUserId
    }

    func toDomain() throws -> User {
        let table = Self.databaseTableName
        guard let role = UserRole(rawValue: role) else { throw DataError.corruptRow(table: table, id: id, column: "role") }
        return User(id: try RecordSupport.uuid(id, table: table, id: id, column: "id"),
                    companyId: try RecordSupport.uuid(companyId, table: table, id: id, column: "company_id"),
                    displayName: displayName, email: email, role: role, authUserId: authUserId,
                    createdAt: try RecordSupport.date(createdAt, table: table, id: id, column: "created_at"),
                    updatedAt: try RecordSupport.date(updatedAt, table: table, id: id, column: "updated_at"),
                    deletedAt: try RecordSupport.date(deletedAt, table: table, id: id, column: "deleted_at"))
    }
}
