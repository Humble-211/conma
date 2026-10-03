import Foundation
import GRDB
import Domain

public final class GRDBCustomerRepository: CustomerRepository {
    private let database: AppDatabase
    private let clock: Clock

    public init(database: AppDatabase, clock: Clock) {
        self.database = database; self.clock = clock
    }

    public func get(id: UUID) async throws -> Customer? {
        try await database.writer.read { db in
            try CustomerRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db)?.toDomain()
        }
    }

    public func list(companyId: UUID) async throws -> [Customer] {
        try await database.writer.read { db in
            try CustomerRecord.filter(Column("company_id") == companyId.dbKey && Column("deleted_at") == nil)
                .order(Column("name").collating(.localizedCaseInsensitiveCompare)).fetchAll(db).map { try $0.toDomain() }
        }
    }

    public func observeAll(companyId: UUID) -> AsyncThrowingStream<[Customer], Error> {
        let key = companyId.dbKey
        let observation = ValueObservation.tracking { db -> [Customer] in
            try CustomerRecord.filter(Column("company_id") == key && Column("deleted_at") == nil)
                .order(Column("name").collating(.localizedCaseInsensitiveCompare)).fetchAll(db).map { try $0.toDomain() }
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

    public func projects(customerId: UUID) async throws -> [Project] {
        try await database.writer.read { db in
            let records = try ProjectRecord.filter(Column("customer_id") == customerId.dbKey && Column("deleted_at") == nil).order(Column("updated_at").desc, Column("name")).fetchAll(db)
            guard let first = records.first else { return [] }
            let currencyRaw = try String.fetchOne(db, sql: "SELECT currency_code FROM companies WHERE id = ?", arguments: [first.companyId]) ?? ""
            guard let currency = CurrencyCode(rawValue: currencyRaw) else { throw DataError.corruptRow(table: "companies", id: first.companyId, column: "currency_code") }
            return try records.map { try $0.toDomain(currency: currency, scopeFields: []) }
        }
    }

    public func save(_ customer: Customer) async throws {
        try customer.validate()
        var stamped = customer
        stamped.updatedAt = clock.now()
        let record = CustomerRecord(stamped)
        try await database.writer.write { db in
            try record.save(db)
        }
    }

    public func softDelete(id: UUID, actor: ActivityActor) async throws {
        let now = clock.now()
        try await database.writer.write { db in
            guard let record = try CustomerRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { throw DataError.notFound }
            let liveProjects = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM projects WHERE customer_id = ? AND deleted_at IS NULL", arguments: [record.id]) ?? 0
            guard liveProjects == 0 else { throw DomainError.customerHasProjects }
            try db.execute(sql: "UPDATE customers SET deleted_at = ?, updated_at = ?, sync_state = 'pending' WHERE id = ?",
                           arguments: [Timestamps.string(now), Timestamps.string(now), record.id])
        }
    }
}
