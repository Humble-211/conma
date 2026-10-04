// Packages/Data/Sources/Data/Repositories/GRDBEmployeeRepository.swift
import Foundation
import GRDB
import Domain

public final class GRDBEmployeeRepository: EmployeeRepository {
    private let database: AppDatabase
    private let clock: Clock

    public init(database: AppDatabase, clock: Clock) { self.database = database; self.clock = clock }

    public func observeAll(companyId: UUID) -> AsyncThrowingStream<[Employee], Error> {
        let key = companyId.dbKey
        let observation = ValueObservation.tracking { db -> [Employee] in
            let currency = try GRDBProjectRepository.currency(db, companyId: key)
            return CrewList.ordered(try EmployeeRecord.fetchLive(db, companyId: key, currency: currency))
        }
        return GRDBInsightsRepository.stream(observation, in: database.writer)
    }

    public func get(id: UUID, includingDeleted: Bool) async throws -> Employee? {
        try await database.writer.read { db in
            var request = EmployeeRecord.filter(Column("id") == id.dbKey)
            if !includingDeleted { request = request.filter(Column("deleted_at") == nil) }
            guard let record = try request.fetchOne(db) else { return nil }
            return try record.toDomain(currency: try GRDBProjectRepository.currency(db, companyId: record.companyId))
        }
    }

    public func create(_ employee: Employee) async throws {
        try employee.validate()
        let now = clock.now()
        var stamped = employee
        stamped.createdAt = now; stamped.updatedAt = now; stamped.deletedAt = nil
        let input = stamped
        try await database.writer.write { db in
            try Self.checkCurrency(db, input)
            try EmployeeRecord(input).insert(db)
        }
    }

    public func update(_ employee: Employee) async throws {
        try employee.validate()
        let now = clock.now()
        let input = employee
        try await database.writer.write { db in
            guard let old = try EmployeeRecord.filter(Column("id") == input.id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { throw DomainError.notFound }
            guard old.companyId == input.companyId.dbKey else { throw DataError.scopeMismatch }
            try Self.checkCurrency(db, input)
            var row = input
            row.createdAt = try RecordSupport.date(old.createdAt, table: "employees", id: old.id, column: "created_at")
            row.updatedAt = try RecordSupport.date(old.updatedAt, table: "employees", id: old.id, column: "updated_at")
            row.deletedAt = nil
            var candidate = EmployeeRecord(row)
            candidate.syncState = old.syncState
            guard candidate != old else { return }
            row.updatedAt = now
            try EmployeeRecord(row).update(db)
        }
    }

    public func softDelete(id: UUID) async throws {
        let stamp = Timestamps.string(clock.now())
        try await database.writer.write { db in
            guard try EmployeeRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) != nil else { throw DomainError.notFound }
            try db.execute(sql: "UPDATE employees SET deleted_at = ?, updated_at = ?, sync_state = 'pending' WHERE id = ?", arguments: [stamp, stamp, id.dbKey])
        }
    }

    private static func checkCurrency(_ db: Database, _ employee: Employee) throws {
        let currency = try GRDBProjectRepository.currency(db, companyId: employee.companyId.dbKey)
        guard [employee.dailyRate, employee.hourlyRate].compactMap({ $0 }).allSatisfy({ $0.currency == currency }) else { throw DomainError.currencyMismatch }
    }
}
