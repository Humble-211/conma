// Packages/Data/Sources/Data/Repositories/GRDBPaymentRepository.swift
import Foundation
import GRDB
import Domain

public final class GRDBPaymentRepository: PaymentRepository {
    private let database: AppDatabase
    private let clock: Clock

    public init(database: AppDatabase, clock: Clock) { self.database = database; self.clock = clock }

    // MARK: Reads

    public func get(id: UUID) async throws -> Payment? {
        try await database.writer.read { db in
            guard let record = try PaymentRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { return nil }
            return try record.toDomain(currency: try GRDBProjectRepository.currency(db, companyId: record.companyId))
        }
    }

    public func lastUsedMethod(companyId: UUID) async throws -> PaymentMethod? {
        try await database.writer.read { db in
            try String.fetchOne(db, sql: "SELECT method FROM payments WHERE company_id = ? AND deleted_at IS NULL ORDER BY created_at DESC, rowid DESC LIMIT 1",
                                arguments: [companyId.dbKey]).flatMap(PaymentMethod.init(rawValue:))
        }
    }

    // MARK: Writes

    public func create(_ payment: Payment, actor: ActivityActor) async throws {
        try payment.validate()
        let now = clock.now()
        var stamped = payment
        stamped.createdAt = now; stamped.updatedAt = now; stamped.deletedAt = nil
        let input = stamped
        try await database.writer.write { db in
            try Self.checkScope(db, input)
            try PaymentRecord(input).insert(db)
            try ActivityLogRecord.append(db, companyId: input.companyId, actor: actor, action: .paymentReceived, entityType: "payment", entityId: input.id,
                                         projectId: input.projectId, details: try Self.details(db, input), at: now)
        }
    }

    public func update(_ payment: Payment, actor: ActivityActor) async throws {
        try payment.validate()
        let now = clock.now()
        let input = payment
        try await database.writer.write { db in
            guard let old = try PaymentRecord.filter(Column("id") == input.id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { throw DomainError.notFound }
            guard old.companyId == input.companyId.dbKey, old.projectId == input.projectId.dbKey else { throw DataError.scopeMismatch }
            try Self.checkScope(db, input)
            let previous = try old.toDomain(currency: try GRDBProjectRepository.currency(db, companyId: old.companyId))
            var row = input
            row.createdAt = previous.createdAt
            row.updatedAt = previous.updatedAt
            row.deletedAt = nil
            var candidate = PaymentRecord(row)
            candidate.syncState = old.syncState
            guard candidate != old else { return }
            row.updatedAt = now
            try PaymentRecord(row).update(db)
            var details = try Self.details(db, row)
            // "from" only when the amount changed; a stage/method/date/notes edit reads as a plain update.
            if previous.amount != row.amount { details["from"] = previous.amount.storageString }
            try ActivityLogRecord.append(db, companyId: row.companyId, actor: actor, action: .paymentUpdated, entityType: "payment", entityId: row.id,
                                         projectId: row.projectId, details: details, at: now)
        }
    }

    public func softDelete(id: UUID, actor: ActivityActor) async throws {
        let now = clock.now()
        let stamp = Timestamps.string(now)
        try await database.writer.write { db in
            guard let record = try PaymentRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { throw DomainError.notFound }
            let payment = try record.toDomain(currency: try GRDBProjectRepository.currency(db, companyId: record.companyId))
            try db.execute(sql: "UPDATE payments SET deleted_at = ?, updated_at = ?, sync_state = 'pending' WHERE id = ?", arguments: [stamp, stamp, record.id])
            try ActivityLogRecord.append(db, companyId: payment.companyId, actor: actor, action: .paymentDeleted, entityType: "payment", entityId: payment.id,
                                         projectId: payment.projectId, details: try Self.details(db, payment), at: now)
        }
    }

    // MARK: Helpers

    /// Currency matches the company; project live in the company; a linked item live AND of the same project
    /// (the composite foreign key cannot see soft deletes).
    static func checkScope(_ db: Database, _ payment: Payment) throws {
        let currency = try GRDBProjectRepository.currency(db, companyId: payment.companyId.dbKey)
        guard payment.amount.currency == currency else { throw DomainError.currencyMismatch }
        try GRDBExpenseRepository.requireLiveProject(db, id: payment.projectId, companyId: payment.companyId)
        if let item = payment.scheduleItemId {
            let live = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM payment_schedule_items WHERE id = ? AND project_id = ? AND company_id = ? AND deleted_at IS NULL",
                                        arguments: [item.dbKey, payment.projectId.dbKey, payment.companyId.dbKey]) ?? 0
            guard live > 0 else { throw DomainError.notFound }
        }
    }

    static func details(_ db: Database, _ payment: Payment) throws -> [String: String] {
        let label = try payment.scheduleItemId.flatMap { try String.fetchOne(db, sql: "SELECT label FROM payment_schedule_items WHERE id = ?", arguments: [$0.dbKey]) } ?? ""
        return ["amount": payment.amount.storageString, "currency": payment.amount.currency.rawValue, "item": label, "method": payment.method.rawValue]
    }
}
