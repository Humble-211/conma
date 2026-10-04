// Packages/Data/Sources/Data/Repositories/GRDBLabourRepository.swift
import Foundation
import GRDB
import Domain

public final class GRDBLabourRepository: LabourRepository {
    private let database: AppDatabase
    private let clock: Clock

    public init(database: AppDatabase, clock: Clock) { self.database = database; self.clock = clock }

    // MARK: Reads

    public func observeProject(id: UUID) -> AsyncThrowingStream<ProjectLabourSnapshot?, Error> {
        let key = id.dbKey
        let observation = ValueObservation.tracking { db -> ProjectLabourSnapshot? in
            guard let project = try ProjectRecord.filter(Column("id") == key && Column("deleted_at") == nil).fetchOne(db) else { return nil }
            let currency = try GRDBProjectRepository.currency(db, companyId: project.companyId)
            return ProjectLabourSnapshot(currency: currency,
                                         entries: try LabourEntryRecord.fetchLive(db, projectId: key, currency: currency),
                                         employees: try EmployeeRecord.fetchAll(db, companyId: project.companyId, currency: currency))
        }
        return GRDBInsightsRepository.stream(observation, in: database.writer)
    }

    public func get(id: UUID) async throws -> LabourEntry? {
        try await database.writer.read { db in
            guard let record = try LabourEntryRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { return nil }
            return try record.toDomain(currency: try GRDBProjectRepository.currency(db, companyId: record.companyId))
        }
    }

    // MARK: Writes

    public func create(_ entries: [LabourEntry], actor: ActivityActor) async throws {
        guard let first = entries.first else { throw DomainError.incompleteLabour }
        guard entries.allSatisfy({ $0.projectId == first.projectId && $0.companyId == first.companyId }) else { throw DataError.scopeMismatch }
        for entry in entries { try entry.validate() }
        let now = clock.now()
        let stamped = entries.map { e -> LabourEntry in var s = e; s.createdAt = now; s.updatedAt = now; s.deletedAt = nil; return s }
        try await database.writer.write { db in
            let currency = try GRDBProjectRepository.currency(db, companyId: first.companyId.dbKey)
            guard stamped.allSatisfy({ $0.dailyRate.currency == currency }) else { throw DomainError.currencyMismatch }
            try GRDBExpenseRepository.requireLiveProject(db, id: first.projectId, companyId: first.companyId)
            var names: [String] = []
            for entry in stamped {
                guard let name = try String.fetchOne(db, sql: "SELECT name FROM employees WHERE id = ? AND company_id = ? AND deleted_at IS NULL",
                                                     arguments: [entry.employeeId.dbKey, entry.companyId.dbKey]) else { throw DomainError.notFound }
                names.append(name)
                try LabourEntryRecord(entry).insert(db)
            }
            let total = try Money.sum(stamped.map(\.cost), currency: currency)
            try ActivityLogRecord.append(db, companyId: first.companyId, actor: actor, action: .labourLogged, entityType: "labour_entry", entityId: first.id,
                                         projectId: first.projectId,
                                         details: ["currency": currency.rawValue, "names": names.joined(separator: ", "), "people": String(stamped.count),
                                                   "total": total.storageString, "workDate": first.workDate.storageString], at: now)
        }
    }

    public func update(_ entry: LabourEntry, actor: ActivityActor) async throws {
        try entry.validate()
        let now = clock.now()
        let input = entry
        try await database.writer.write { db in
            guard let old = try LabourEntryRecord.filter(Column("id") == input.id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { throw DomainError.notFound }
            guard old.companyId == input.companyId.dbKey, old.projectId == input.projectId.dbKey, old.employeeId == input.employeeId.dbKey else { throw DataError.scopeMismatch }
            let currency = try GRDBProjectRepository.currency(db, companyId: old.companyId)
            guard input.dailyRate.currency == currency else { throw DomainError.currencyMismatch }
            try GRDBExpenseRepository.requireLiveProject(db, id: input.projectId, companyId: input.companyId)
            let previous = try old.toDomain(currency: currency)
            var row = input
            row.createdAt = previous.createdAt
            row.updatedAt = previous.updatedAt
            row.deletedAt = nil
            var candidate = LabourEntryRecord(row)
            candidate.syncState = old.syncState
            guard candidate != old else { return }
            row.updatedAt = now
            try LabourEntryRecord(row).update(db)
            var details = try Self.details(db, row, currency: currency)
            details["from"] = previous.cost.storageString
            try ActivityLogRecord.append(db, companyId: row.companyId, actor: actor, action: .labourUpdated, entityType: "labour_entry", entityId: row.id,
                                         projectId: row.projectId, details: details, at: now)
        }
    }

    public func softDelete(id: UUID, actor: ActivityActor) async throws {
        let now = clock.now()
        let stamp = Timestamps.string(now)
        try await database.writer.write { db in
            guard let record = try LabourEntryRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { throw DomainError.notFound }
            let currency = try GRDBProjectRepository.currency(db, companyId: record.companyId)
            let entry = try record.toDomain(currency: currency)
            try db.execute(sql: "UPDATE labour_entries SET deleted_at = ?, updated_at = ?, sync_state = 'pending' WHERE id = ?", arguments: [stamp, stamp, record.id])
            try ActivityLogRecord.append(db, companyId: entry.companyId, actor: actor, action: .labourDeleted, entityType: "labour_entry", entityId: entry.id,
                                         projectId: entry.projectId, details: try Self.details(db, entry, currency: currency), at: now)
        }
    }

    /// One-person details; the name is read even when the employee left the crew.
    static func details(_ db: Database, _ entry: LabourEntry, currency: CurrencyCode) throws -> [String: String] {
        let name = try String.fetchOne(db, sql: "SELECT name FROM employees WHERE id = ?", arguments: [entry.employeeId.dbKey]) ?? ""
        return ["currency": currency.rawValue, "names": name, "people": "1", "total": entry.cost.storageString, "workDate": entry.workDate.storageString]
    }
}
