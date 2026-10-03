import Foundation
import GRDB
import Domain

public final class GRDBProjectEstimateRepository: ProjectEstimateRepository {
    private let database: AppDatabase
    private let clock: Clock

    public init(database: AppDatabase, clock: Clock) { self.database = database; self.clock = clock }

    public func lines(projectId: UUID) async throws -> [ProjectEstimateLine] {
        try await database.writer.read { db in
            let currency = try CompanyLookup.currency(db, projectId: projectId.dbKey)
            return try ProjectEstimateLineRecord.fetchLive(db, projectId: projectId.dbKey, currency: currency)
        }
    }

    public func replace(projectId: UUID, group: CostGroup, change: EstimateLineChange, actor: ActivityActor) async throws {
        guard change.upserts.allSatisfy({ $0.projectId == projectId && $0.costGroup == group }) else { throw DataError.scopeMismatch }
        let now = clock.now()
        let stamp = Timestamps.string(now)
        let records = change.upserts.map { line -> ProjectEstimateLineRecord in var l = line; l.updatedAt = now; return ProjectEstimateLineRecord(l) }
        let deletedKeys = change.deletedIds.map(\.dbKey)
        let pid = projectId.dbKey
        try await database.writer.write { db in
            guard let projectRow = try Row.fetchOne(db, sql: "SELECT company_id FROM projects WHERE id = ? AND deleted_at IS NULL", arguments: [pid]) else { throw DataError.notFound }
            let companyKey: String = projectRow["company_id"]
            for key in deletedKeys {
                try db.execute(sql: "UPDATE project_estimate_lines SET deleted_at = ?, updated_at = ?, sync_state = 'pending' WHERE id = ? AND project_id = ? AND cost_group = ? AND deleted_at IS NULL",
                               arguments: [stamp, stamp, key, pid, group.rawValue])
            }
            for record in records { try record.save(db) }
            if change.totalBefore != change.totalAfter {
                let companyId = try RecordSupport.uuid(companyKey, table: "projects", id: pid, column: "company_id")
                try ActivityLogRecord.append(db, companyId: companyId, actor: actor, action: .estimateChanged, entityType: "project", entityId: projectId, projectId: projectId,
                                             details: ["group": group.rawValue, "from": change.totalBefore.storageString, "to": change.totalAfter.storageString], at: now)
            }
        }
    }
}

/// Shared read helper: the company currency of a project.
enum CompanyLookup {
    static func currency(_ db: Database, projectId: String) throws -> CurrencyCode {
        guard let raw = try String.fetchOne(db, sql: "SELECT c.currency_code FROM projects p JOIN companies c ON c.id = p.company_id WHERE p.id = ?", arguments: [projectId]),
              let currency = CurrencyCode(rawValue: raw) else { throw DataError.notFound }
        return currency
    }
}
