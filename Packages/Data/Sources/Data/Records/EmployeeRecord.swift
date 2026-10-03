import Foundation
import GRDB
import Domain

struct EmployeeRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "employees"
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
    var role: String?
    var trade: String?
    var hourlyRate: String?
    var dailyRate: String?
    var certifications: String?
    var emergencyContact: String?
    var notes: String?

    init(_ e: Employee) {
        id = e.id.dbKey; companyId = e.companyId.dbKey
        createdAt = Timestamps.string(e.createdAt); updatedAt = Timestamps.string(e.updatedAt)
        deletedAt = e.deletedAt.map(Timestamps.string); syncState = SyncState.pending.rawValue
        name = e.name; phone = e.phone; role = e.role; trade = e.trade
        hourlyRate = e.hourlyRate?.storageString; dailyRate = e.dailyRate?.storageString
        certifications = e.certifications; emergencyContact = e.emergencyContact; notes = e.notes
    }

    func toDomain(currency: CurrencyCode) throws -> Employee {
        let t = Self.databaseTableName
        let hourly = try hourlyRate.map { try RecordSupport.money($0, currency: currency, table: t, id: id, column: "hourly_rate") }
        let daily = try dailyRate.map { try RecordSupport.money($0, currency: currency, table: t, id: id, column: "daily_rate") }
        return Employee(id: try RecordSupport.uuid(id, table: t, id: id, column: "id"),
                        companyId: try RecordSupport.uuid(companyId, table: t, id: id, column: "company_id"),
                        name: name, phone: phone, role: role, trade: trade, hourlyRate: hourly, dailyRate: daily,
                        certifications: certifications, emergencyContact: emergencyContact, notes: notes,
                        createdAt: try RecordSupport.date(createdAt, table: t, id: id, column: "created_at"),
                        updatedAt: try RecordSupport.date(updatedAt, table: t, id: id, column: "updated_at"),
                        deletedAt: try RecordSupport.date(deletedAt, table: t, id: id, column: "deleted_at"))
    }

    static func fetchLive(_ db: Database, companyId: String, currency: CurrencyCode) throws -> [Employee] {
        try EmployeeRecord.filter(Column("company_id") == companyId && Column("deleted_at") == nil)
            .order(Column("name")).fetchAll(db).map { try $0.toDomain(currency: currency) }
    }
}
