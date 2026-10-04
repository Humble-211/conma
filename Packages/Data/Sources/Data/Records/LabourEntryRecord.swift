import Foundation
import GRDB
import Domain

struct LabourEntryRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "labour_entries"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

    var id: String
    var companyId: String
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?
    var syncState: String
    var projectId: String
    var employeeId: String
    var workDate: String
    var days: String
    var dailyRate: String
    var notes: String?

    init(_ l: LabourEntry) {
        id = l.id.dbKey; companyId = l.companyId.dbKey; projectId = l.projectId.dbKey; employeeId = l.employeeId.dbKey
        createdAt = Timestamps.string(l.createdAt); updatedAt = Timestamps.string(l.updatedAt)
        deletedAt = l.deletedAt.map(Timestamps.string); syncState = SyncState.pending.rawValue
        workDate = l.workDate.storageString; days = "\(l.days)"; dailyRate = l.dailyRate.storageString; notes = l.notes
    }

    func toDomain(currency: CurrencyCode) throws -> LabourEntry {
        let t = Self.databaseTableName
        guard let daysValue = try RecordSupport.decimal(days, table: t, id: id, column: "days") else { throw DataError.corruptRow(table: t, id: id, column: "days") }
        return LabourEntry(id: try RecordSupport.uuid(id, table: t, id: id, column: "id"),
                           companyId: try RecordSupport.uuid(companyId, table: t, id: id, column: "company_id"),
                           projectId: try RecordSupport.uuid(projectId, table: t, id: id, column: "project_id"),
                           employeeId: try RecordSupport.uuid(employeeId, table: t, id: id, column: "employee_id"),
                           workDate: try RecordSupport.requiredCalendarDate(workDate, table: t, id: id, column: "work_date"),
                           days: daysValue, dailyRate: try RecordSupport.money(dailyRate, currency: currency, table: t, id: id, column: "daily_rate"), notes: notes,
                           createdAt: try RecordSupport.date(createdAt, table: t, id: id, column: "created_at"),
                           updatedAt: try RecordSupport.date(updatedAt, table: t, id: id, column: "updated_at"),
                           deletedAt: try RecordSupport.date(deletedAt, table: t, id: id, column: "deleted_at"))
    }

    static func fetchLive(_ db: Database, projectId: String, currency: CurrencyCode) throws -> [LabourEntry] {
        try LabourEntryRecord.filter(Column("project_id") == projectId && Column("deleted_at") == nil)
            .order(Column("work_date"), Column.rowID).fetchAll(db).map { try $0.toDomain(currency: currency) }
    }

    static func fetchLive(_ db: Database, companyId: String, currency: CurrencyCode) throws -> [LabourEntry] {
        try LabourEntryRecord.filter(Column("company_id") == companyId && Column("deleted_at") == nil)
            .order(Column("work_date"), Column.rowID).fetchAll(db).map { try $0.toDomain(currency: currency) }
    }
}
