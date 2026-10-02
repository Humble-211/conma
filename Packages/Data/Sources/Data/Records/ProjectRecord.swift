import Foundation
import GRDB
import Domain

struct ProjectRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "projects"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

    var id: String
    var companyId: String
    var createdAt: String
    var updatedAt: String
    var deletedAt: String?
    var syncState: String
    var customerId: String
    var name: String
    var jobType: String
    var customJobType: String?
    var status: String
    var addressLine: String
    var unit: String?
    var city: String?
    var region: String?
    var postalCode: String?
    var scopeDescription: String?
    var startDate: String?
    var estimatedCompletionDate: String?
    var workingDays: Int?
    var hoursPerDay: String?
    var workersPerDay: Int?
    var contractValue: String
    var manualProgress: Int?
    var depositRequiredToStart: Bool

    init(_ p: Project) {
        id = p.id.dbKey; companyId = p.companyId.dbKey; customerId = p.customerId.dbKey
        createdAt = Timestamps.string(p.createdAt); updatedAt = Timestamps.string(p.updatedAt)
        deletedAt = p.deletedAt.map(Timestamps.string); syncState = SyncState.pending.rawValue
        name = p.name; jobType = p.jobType.rawValue; customJobType = p.customJobType; status = p.status.rawValue
        addressLine = p.address.line; unit = p.address.unit; city = p.address.city; region = p.address.region; postalCode = p.address.postalCode
        scopeDescription = p.scopeDescription
        startDate = p.startDate?.storageString; estimatedCompletionDate = p.estimatedCompletionDate?.storageString
        workingDays = p.workingDays; hoursPerDay = p.hoursPerDay.map { "\($0)" }; workersPerDay = p.workersPerDay
        contractValue = p.contractValue.storageString; manualProgress = p.manualProgress; depositRequiredToStart = p.depositRequiredToStart
    }

    func toDomain(currency: CurrencyCode, scopeFields: [ProjectScopeField]) throws -> Project {
        let t = Self.databaseTableName
        guard let jobType = JobType(rawValue: jobType) else { throw DataError.corruptRow(table: t, id: id, column: "job_type") }
        guard let status = ProjectStatus(rawValue: status) else { throw DataError.corruptRow(table: t, id: id, column: "status") }
        return Project(id: try RecordSupport.uuid(id, table: t, id: id, column: "id"),
                       companyId: try RecordSupport.uuid(companyId, table: t, id: id, column: "company_id"),
                       customerId: try RecordSupport.uuid(customerId, table: t, id: id, column: "customer_id"),
                       name: name, jobType: jobType, customJobType: customJobType, status: status,
                       address: Address(line: addressLine, unit: unit, city: city, region: region, postalCode: postalCode),
                       scopeDescription: scopeDescription, scopeFields: scopeFields,
                       startDate: try RecordSupport.calendarDate(startDate, table: t, id: id, column: "start_date"),
                       estimatedCompletionDate: try RecordSupport.calendarDate(estimatedCompletionDate, table: t, id: id, column: "estimated_completion_date"),
                       workingDays: workingDays, hoursPerDay: try RecordSupport.decimal(hoursPerDay, table: t, id: id, column: "hours_per_day"), workersPerDay: workersPerDay,
                       contractValue: try RecordSupport.money(contractValue, currency: currency, table: t, id: id, column: "contract_value"),
                       manualProgress: manualProgress, depositRequiredToStart: depositRequiredToStart,
                       createdAt: try RecordSupport.date(createdAt, table: t, id: id, column: "created_at"),
                       updatedAt: try RecordSupport.date(updatedAt, table: t, id: id, column: "updated_at"),
                       deletedAt: try RecordSupport.date(deletedAt, table: t, id: id, column: "deleted_at"))
    }
}
