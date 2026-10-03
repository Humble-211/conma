import Foundation
import GRDB
import Domain

public final class GRDBPaymentScheduleRepository: PaymentScheduleRepository {
    private let database: AppDatabase
    private let clock: Clock

    public init(database: AppDatabase, clock: Clock) { self.database = database; self.clock = clock }

    public func items(projectId: UUID) async throws -> [PaymentScheduleItem] {
        try await database.writer.read { db in
            let currency = try CompanyLookup.currency(db, projectId: projectId.dbKey)
            return try PaymentScheduleItemRecord.fetchLive(db, projectId: projectId.dbKey, currency: currency)
        }
    }

    public func replace(projectId: UUID, change: ScheduleItemChange, actor: ActivityActor) async throws {
        guard change.upserts.allSatisfy({ $0.projectId == projectId }) else { throw DataError.scopeMismatch }
        let now = clock.now()
        let stamp = Timestamps.string(now)
        let records = change.upserts.map { item -> PaymentScheduleItemRecord in var i = item; i.updatedAt = now; return PaymentScheduleItemRecord(i) }
        let deletedKeys = change.deletedIds.map(\.dbKey)
        let pid = projectId.dbKey
        try await database.writer.write { db in
            guard let projectRow = try Row.fetchOne(db, sql: "SELECT company_id FROM projects WHERE id = ? AND deleted_at IS NULL", arguments: [pid]) else { throw DataError.notFound }
            let companyKey: String = projectRow["company_id"]
            for key in deletedKeys {
                try db.execute(sql: "UPDATE payments SET schedule_item_id = NULL, updated_at = ?, sync_state = 'pending' WHERE schedule_item_id = ? AND deleted_at IS NULL", arguments: [stamp, key])
                try db.execute(sql: "UPDATE payment_schedule_items SET deleted_at = ?, updated_at = ?, sync_state = 'pending' WHERE id = ? AND project_id = ? AND deleted_at IS NULL",
                               arguments: [stamp, stamp, key, pid])
            }
            for record in records { try record.save(db) }
            if change.totalBefore != change.totalAfter {
                let companyId = try RecordSupport.uuid(companyKey, table: "projects", id: pid, column: "company_id")
                try ActivityLogRecord.append(db, companyId: companyId, actor: actor, action: .scheduleChanged, entityType: "project", entityId: projectId, projectId: projectId,
                                             details: ["from": change.totalBefore.storageString, "to": change.totalAfter.storageString], at: now)
            }
        }
    }
}
