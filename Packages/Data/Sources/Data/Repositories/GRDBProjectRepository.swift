import Foundation
import GRDB
import Domain

public final class GRDBProjectRepository: ProjectRepository {
    private let database: AppDatabase
    private let clock: Clock

    public init(database: AppDatabase, clock: Clock) {
        self.database = database; self.clock = clock
    }

    // MARK: Reads

    public func get(id: UUID) async throws -> Project? {
        try await database.writer.read { db in
            guard let record = try ProjectRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { return nil }
            let currency = try Self.currency(db, companyId: record.companyId)
            let fields = try Self.scopeFields(db, projectIds: [record.id])[record.id] ?? []
            return try record.toDomain(currency: currency, scopeFields: fields)
        }
    }

    public func list(companyId: UUID) async throws -> [Project] {
        try await database.writer.read { db in
            let records = try ProjectRecord.filter(Column("company_id") == companyId.dbKey && Column("deleted_at") == nil).order(Column("updated_at").desc).fetchAll(db)
            let currency = try Self.currency(db, companyId: companyId.dbKey)
            let fields = try Self.scopeFields(db, projectIds: records.map(\.id))
            return try records.map { try $0.toDomain(currency: currency, scopeFields: fields[$0.id] ?? []) }
        }
    }

    public func observeSummaries(companyId: UUID) -> AsyncThrowingStream<[ProjectSummary], Error> {
        let key = companyId.dbKey
        let observation = ValueObservation.tracking { db -> [ProjectSummary] in
            let currency = try Self.currency(db, companyId: key)
            let rows = try Row.fetchAll(db, sql: """
                SELECT p.*, c.name AS customer_name
                FROM projects p JOIN customers c ON c.id = p.customer_id
                WHERE p.company_id = ? AND p.deleted_at IS NULL
                ORDER BY p.updated_at DESC, p.name
                """, arguments: [key])
            let records = try rows.map { try ProjectRecord(row: $0) }
            let fields = try Self.scopeFields(db, projectIds: records.map(\.id))
            return try zip(records, rows).map { record, row in
                ProjectSummary(project: try record.toDomain(currency: currency, scopeFields: fields[record.id] ?? []), customerName: row["customer_name"])
            }
        }
        let writer = database.writer
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await value in observation.values(in: writer) { continuation.yield(value) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func observeDetail(id: UUID) -> AsyncThrowingStream<ProjectDetailSnapshot?, Error> {
        let key = id.dbKey
        let observation = ValueObservation.tracking { db -> ProjectDetailSnapshot? in
            guard let record = try ProjectRecord.filter(Column("id") == key && Column("deleted_at") == nil).fetchOne(db) else { return nil }
            let currency = try Self.currency(db, companyId: record.companyId)
            let fields = try Self.scopeFields(db, projectIds: [record.id])[record.id] ?? []
            let project = try record.toDomain(currency: currency, scopeFields: fields)
            guard let customerRecord = try CustomerRecord.filter(Column("id") == record.customerId).fetchOne(db) else {
                throw DataError.corruptRow(table: "projects", id: record.id, column: "customer_id")
            }
            return ProjectDetailSnapshot(project: project, customer: try customerRecord.toDomain(),
                                         estimateLines: try ProjectEstimateLineRecord.fetchLive(db, projectId: record.id, currency: currency),
                                         scheduleItems: try PaymentScheduleItemRecord.fetchLive(db, projectId: record.id, currency: currency))
        }
        let writer = database.writer
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await value in observation.values(in: writer) { continuation.yield(value) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Writes

    public func create(_ bundle: NewProjectBundle, actor: ActivityActor) async throws {
        try bundle.project.validate()
        try bundle.newCustomer?.validate()
        let now = clock.now()
        let projectRecord = ProjectRecord(bundle.project)
        let fieldRecords = bundle.scopeFields.map { ProjectScopeFieldRecord($0) }
        let lineRecords = bundle.estimateLines.map { ProjectEstimateLineRecord($0) }
        let itemRecords = bundle.scheduleItems.map { PaymentScheduleItemRecord($0) }
        let customerRecord = bundle.newCustomer.map { CustomerRecord($0) }
        let project = bundle.project
        let newCustomer = bundle.newCustomer
        try await database.writer.write { db in
            let currency = try Self.currency(db, companyId: project.companyId.dbKey)
            guard project.contractValue.currency == currency else { throw DomainError.currencyMismatch }
            if let customerRecord, let newCustomer {
                try customerRecord.insert(db)
                try ActivityLogRecord.append(db, companyId: project.companyId, actor: actor, action: .customerCreated, entityType: "customer", entityId: newCustomer.id, projectId: nil,
                                             details: ["name": newCustomer.name], at: now)
            }
            try projectRecord.insert(db)
            for record in fieldRecords { try record.insert(db) }
            for record in lineRecords { try record.insert(db) }
            for record in itemRecords { try record.insert(db) }
            try ActivityLogRecord.append(db, companyId: project.companyId, actor: actor, action: .projectCreated, entityType: "project", entityId: project.id, projectId: project.id,
                                         details: ["name": project.name, "contractValue": project.contractValue.storageString,
                                                   "estimateLines": String(lineRecords.count), "scheduleItems": String(itemRecords.count)], at: now)
        }
    }

    public func save(_ project: Project, actor: ActivityActor) async throws {
        try project.validate()
        let now = clock.now()
        var stamped = project
        stamped.updatedAt = now
        // Ruling 7: the @Sendable write closure must not capture a mutated `var`.
        let stampedProject = stamped
        let record = ProjectRecord(stampedProject)
        try await database.writer.write { db in
            let currency = try Self.currency(db, companyId: stampedProject.companyId.dbKey)
            guard stampedProject.contractValue.currency == currency else { throw DomainError.currencyMismatch }
            let existing = try ProjectRecord.filter(Column("id") == stampedProject.id.dbKey).fetchOne(db)
            if let existing, existing.deletedAt != nil { throw DataError.notFound }
            try record.save(db)
            try Self.replaceScopeFields(db, project: stampedProject, now: now)

            if let old = existing {
                if old.contractValue != stampedProject.contractValue.storageString {
                    try ActivityLogRecord.append(db, companyId: stampedProject.companyId, actor: actor, action: .contractValueChanged, entityType: "project", entityId: stampedProject.id, projectId: stampedProject.id,
                                                 details: ["from": old.contractValue, "to": stampedProject.contractValue.storageString], at: now)
                }
                if old.status != stampedProject.status.rawValue {
                    try ActivityLogRecord.append(db, companyId: stampedProject.companyId, actor: actor, action: .statusChanged, entityType: "project", entityId: stampedProject.id, projectId: stampedProject.id,
                                                 details: ["from": old.status, "to": stampedProject.status.rawValue], at: now)
                }
                if old.manualProgress != stampedProject.manualProgress {
                    try ActivityLogRecord.append(db, companyId: stampedProject.companyId, actor: actor, action: .progressChanged, entityType: "project", entityId: stampedProject.id, projectId: stampedProject.id,
                                                 details: ["from": old.manualProgress.map(String.init) ?? "", "to": stampedProject.manualProgress.map(String.init) ?? ""], at: now)
                }
            } else {
                try ActivityLogRecord.append(db, companyId: stampedProject.companyId, actor: actor, action: .projectCreated, entityType: "project", entityId: stampedProject.id, projectId: stampedProject.id,
                                             details: ["name": stampedProject.name, "contractValue": stampedProject.contractValue.storageString], at: now)
            }
        }
    }

    public func softDelete(id: UUID, actor: ActivityActor) async throws {
        let now = clock.now()
        let stamp = Timestamps.string(now)
        try await database.writer.write { db in
            guard let record = try ProjectRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { throw DomainError.notFound }
            let pid = record.id
            let set = "SET deleted_at = ?, updated_at = ?, sync_state = 'pending'"
            try db.execute(sql: "UPDATE projects \(set) WHERE id = ?", arguments: [stamp, stamp, pid])
            for table in ["project_scope_fields", "project_estimate_lines", "project_tasks", "project_workers", "payment_schedule_items", "payments",
                          "expenses", "labour_entries", "daily_logs", "photos", "notifications"] {
                try db.execute(sql: "UPDATE \(table) \(set) WHERE project_id = ? AND deleted_at IS NULL", arguments: [stamp, stamp, pid])
            }
            try db.execute(sql: "UPDATE task_checklist_items \(set) WHERE deleted_at IS NULL AND task_id IN (SELECT id FROM project_tasks WHERE project_id = ?)", arguments: [stamp, stamp, pid])
            try db.execute(sql: "UPDATE task_assignees \(set) WHERE deleted_at IS NULL AND task_id IN (SELECT id FROM project_tasks WHERE project_id = ?)", arguments: [stamp, stamp, pid])
            try db.execute(sql: "UPDATE receipt_images \(set) WHERE deleted_at IS NULL AND expense_id IN (SELECT id FROM expenses WHERE project_id = ?)", arguments: [stamp, stamp, pid])
            let companyId = try RecordSupport.uuid(record.companyId, table: "projects", id: pid, column: "company_id")
            try ActivityLogRecord.append(db, companyId: companyId, actor: actor, action: .projectDeleted, entityType: "project", entityId: id, projectId: id, details: ["name": record.name], at: now)
        }
    }

    public func changeStatus(id: UUID, to status: ProjectStatus, actor: ActivityActor) async throws {
        let now = clock.now()
        let stamp = Timestamps.string(now)
        try await database.writer.write { db in
            guard let record = try ProjectRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { throw DomainError.notFound }
            guard record.status != status.rawValue else { return }
            try db.execute(sql: "UPDATE projects SET status = ?, updated_at = ?, sync_state = 'pending' WHERE id = ?", arguments: [status.rawValue, stamp, record.id])
            let companyId = try RecordSupport.uuid(record.companyId, table: "projects", id: record.id, column: "company_id")
            try ActivityLogRecord.append(db, companyId: companyId, actor: actor, action: .statusChanged, entityType: "project", entityId: id, projectId: id,
                                         details: ["from": record.status, "to": status.rawValue], at: now)
        }
    }

    public func setManualProgress(id: UUID, to value: Int?, actor: ActivityActor) async throws {
        if let v = value, !(0...100).contains(v) { throw DomainError.invalidProgress }
        let now = clock.now()
        let stamp = Timestamps.string(now)
        try await database.writer.write { db in
            guard let record = try ProjectRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { throw DomainError.notFound }
            guard record.manualProgress != value else { return }
            try db.execute(sql: "UPDATE projects SET manual_progress = ?, updated_at = ?, sync_state = 'pending' WHERE id = ?", arguments: [value, stamp, record.id])
            let companyId = try RecordSupport.uuid(record.companyId, table: "projects", id: record.id, column: "company_id")
            try ActivityLogRecord.append(db, companyId: companyId, actor: actor, action: .progressChanged, entityType: "project", entityId: id, projectId: id,
                                         details: ["from": record.manualProgress.map(String.init) ?? "", "to": value.map(String.init) ?? ""], at: now)
        }
    }

    public func changeCustomer(id: UUID, to customerId: UUID, actor: ActivityActor) async throws {
        let now = clock.now()
        let stamp = Timestamps.string(now)
        try await database.writer.write { db in
            guard let record = try ProjectRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { throw DomainError.notFound }
            guard let target = try CustomerRecord.filter(Column("id") == customerId.dbKey).fetchOne(db) else { throw DomainError.notFound }
            guard target.deletedAt == nil else { throw DomainError.customerDeleted }
            guard target.companyId == record.companyId else { throw DomainError.crossCompany }
            guard target.id != record.customerId else { return }
            let fromName = try String.fetchOne(db, sql: "SELECT name FROM customers WHERE id = ?", arguments: [record.customerId]) ?? ""
            try db.execute(sql: "UPDATE projects SET customer_id = ?, updated_at = ?, sync_state = 'pending' WHERE id = ?", arguments: [target.id, stamp, record.id])
            let companyId = try RecordSupport.uuid(record.companyId, table: "projects", id: record.id, column: "company_id")
            try ActivityLogRecord.append(db, companyId: companyId, actor: actor, action: .customerChanged, entityType: "project", entityId: id, projectId: id,
                                         details: ["from": fromName, "to": target.name, "fromId": record.customerId, "toId": target.id], at: now)
        }
    }

    // MARK: Helpers

    static func currency(_ db: Database, companyId: String) throws -> CurrencyCode {
        guard let raw = try String.fetchOne(db, sql: "SELECT currency_code FROM companies WHERE id = ?", arguments: [companyId]),
              let currency = CurrencyCode(rawValue: raw) else { throw DataError.corruptRow(table: "companies", id: companyId, column: "currency_code") }
        return currency
    }

    static func scopeFields(_ db: Database, projectIds: [String]) throws -> [String: [ProjectScopeField]] {
        guard !projectIds.isEmpty else { return [:] }
        let records = try ProjectScopeFieldRecord.filter(projectIds.contains(Column("project_id")) && Column("deleted_at") == nil).order(Column("sort_order")).fetchAll(db)
        var result: [String: [ProjectScopeField]] = [:]
        for record in records { result[record.projectId, default: []].append(try record.toDomain()) }
        return result
    }

    /// Upserts the given fields and soft-deletes live fields that are no longer present.
    private static func replaceScopeFields(_ db: Database, project: Project, now: Date) throws {
        let keep = Set(project.scopeFields.map { $0.id.dbKey })
        let live = try ProjectScopeFieldRecord.filter(Column("project_id") == project.id.dbKey && Column("deleted_at") == nil).fetchAll(db)
        let stamp = Timestamps.string(now)
        for record in live where !keep.contains(record.id) {
            try db.execute(sql: "UPDATE project_scope_fields SET deleted_at = ?, updated_at = ?, sync_state = 'pending' WHERE id = ?", arguments: [stamp, stamp, record.id])
        }
        for var field in project.scopeFields {
            field.updatedAt = now
            try ProjectScopeFieldRecord(field).save(db)
        }
    }
}
