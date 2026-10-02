import Foundation
import GRDB
import Domain

struct CustomerRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "customers"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

    var id: String
    var companyId: String
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?
    var syncState: String
    var name: String
    var phone: String?
    var email: String?
    var preferredContact: String?
    var companyName: String?
    var secondaryContact: String?
    var notes: String?

    init(_ c: Customer) {
        id = c.id.dbKey; companyId = c.companyId.dbKey
        createdAt = Timestamps.string(c.createdAt); updatedAt = Timestamps.string(c.updatedAt)
        deletedAt = c.deletedAt.map(Timestamps.string); syncState = SyncState.pending.rawValue
        name = c.name; phone = c.phone; email = c.email; preferredContact = c.preferredContact?.rawValue
        companyName = c.companyName; secondaryContact = c.secondaryContact; notes = c.notes
    }

    func toDomain() throws -> Customer {
        let table = Self.databaseTableName
        let contact = try preferredContact.map { raw -> ContactMethod in
            guard let v = ContactMethod(rawValue: raw) else { throw DataError.corruptRow(table: table, id: id, column: "preferred_contact") }
            return v
        }
        return Customer(id: try RecordSupport.uuid(id, table: table, id: id, column: "id"),
                        companyId: try RecordSupport.uuid(companyId, table: table, id: id, column: "company_id"),
                        name: name, phone: phone, email: email, preferredContact: contact, companyName: companyName,
                        secondaryContact: secondaryContact, notes: notes,
                        createdAt: try RecordSupport.date(createdAt, table: table, id: id, column: "created_at"),
                        updatedAt: try RecordSupport.date(updatedAt, table: table, id: id, column: "updated_at"),
                        deletedAt: try RecordSupport.date(deletedAt, table: table, id: id, column: "deleted_at"))
    }
}
