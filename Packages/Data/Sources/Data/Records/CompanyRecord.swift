import Foundation
import GRDB
import Domain

struct CompanyRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "companies"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

    var id: String
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?
    var syncState: String
    var name: String
    var currencyCode: String

    init(_ company: Company) {
        id = company.id.dbKey
        createdAt = Timestamps.string(company.createdAt)
        updatedAt = Timestamps.string(company.updatedAt)
        deletedAt = company.deletedAt.map(Timestamps.string)
        syncState = SyncState.pending.rawValue
        name = company.name
        currencyCode = company.currencyCode.rawValue
    }

    func toDomain() throws -> Company {
        let table = Self.databaseTableName
        guard let currency = CurrencyCode(rawValue: currencyCode) else { throw DataError.corruptRow(table: table, id: id, column: "currency_code") }
        return Company(id: try RecordSupport.uuid(id, table: table, id: id, column: "id"), name: name, currencyCode: currency,
                       createdAt: try RecordSupport.date(createdAt, table: table, id: id, column: "created_at"),
                       updatedAt: try RecordSupport.date(updatedAt, table: table, id: id, column: "updated_at"),
                       deletedAt: try RecordSupport.date(deletedAt, table: table, id: id, column: "deleted_at"))
    }
}
