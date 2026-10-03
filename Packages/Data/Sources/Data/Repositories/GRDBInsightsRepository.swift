import Foundation
import GRDB
import Domain

public final class GRDBInsightsRepository: InsightsRepository {
    private let database: AppDatabase
    public init(database: AppDatabase) { self.database = database }

    public func observeDashboard(companyId: UUID) -> AsyncThrowingStream<DashboardInputs.Snapshot, Error> {
        let key = companyId.dbKey
        let observation = ValueObservation.tracking { db -> DashboardInputs.Snapshot in
            guard let companyRecord = try CompanyRecord.filter(Column("id") == key && Column("deleted_at") == nil).fetchOne(db) else { throw DataError.notFound }
            let company = try companyRecord.toDomain()
            let currency = company.currencyCode
            let projectRecords = try ProjectRecord.filter(Column("company_id") == key && Column("deleted_at") == nil).fetchAll(db)
            let fields = try GRDBProjectRepository.scopeFields(db, projectIds: projectRecords.map(\.id))
            let projects = try projectRecords.map { try $0.toDomain(currency: currency, scopeFields: fields[$0.id] ?? []) }
            return DashboardInputs.Snapshot(
                company: company, projects: projects,
                customers: try CustomerRecord.filter(Column("company_id") == key && Column("deleted_at") == nil).fetchAll(db).map { try $0.toDomain() },
                estimateLines: try ProjectEstimateLineRecord.fetchLive(db, companyId: key, currency: currency),
                scheduleItems: try PaymentScheduleItemRecord.fetchLive(db, companyId: key, currency: currency),
                expenses: try ExpenseRecord.fetchLive(db, companyId: key, currency: currency),
                labourEntries: try LabourEntryRecord.fetchLive(db, companyId: key, currency: currency),
                payments: try PaymentRecord.fetchLive(db, companyId: key, currency: currency))
        }
        return Self.stream(observation, in: database.writer)
    }

    public func observeProject(id: UUID) -> AsyncThrowingStream<ProjectInsightsInputs.Snapshot?, Error> {
        let key = id.dbKey
        let observation = ValueObservation.tracking { db -> ProjectInsightsInputs.Snapshot? in
            guard let record = try ProjectRecord.filter(Column("id") == key && Column("deleted_at") == nil).fetchOne(db) else { return nil }
            let currency = try GRDBProjectRepository.currency(db, companyId: record.companyId)
            let fields = try GRDBProjectRepository.scopeFields(db, projectIds: [key])
            let project = try record.toDomain(currency: currency, scopeFields: fields[key] ?? [])
            return ProjectInsightsInputs.Snapshot(
                project: project,
                estimateLines: try ProjectEstimateLineRecord.fetchLive(db, projectId: key, currency: currency),
                scheduleItems: try PaymentScheduleItemRecord.fetchLive(db, projectId: key, currency: currency),
                expenses: try ExpenseRecord.fetchLive(db, projectId: key, currency: currency),
                labourEntries: try LabourEntryRecord.fetchLive(db, projectId: key, currency: currency),
                payments: try PaymentRecord.fetchLive(db, projectId: key, currency: currency))
        }
        return Self.stream(observation, in: database.writer)
    }

    static func stream<Reducer: ValueReducer>(_ observation: ValueObservation<Reducer>, in writer: any DatabaseWriter) -> AsyncThrowingStream<Reducer.Value, Error>
    where Reducer.Value: Sendable {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await value in observation.values(in: writer) { continuation.yield(value) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
