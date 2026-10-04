// Packages/Data/Sources/Data/Repositories/GRDBCustomCategoryRepository.swift
import Foundation
import GRDB
import Domain

public final class GRDBCustomCategoryRepository: CustomCategoryRepository {
    private let database: AppDatabase
    private let clock: Clock

    public init(database: AppDatabase, clock: Clock) { self.database = database; self.clock = clock }

    public func observeAll(companyId: UUID) -> AsyncThrowingStream<[CustomCategoryUsage], Error> {
        let key = companyId.dbKey
        let observation = ValueObservation.tracking { db -> [CustomCategoryUsage] in
            let rows = try Row.fetchAll(db, sql: """
                SELECT c.*,
                       (SELECT COUNT(*) FROM expenses e WHERE e.custom_category_id = c.id AND e.deleted_at IS NULL) AS live_count,
                       (SELECT COUNT(*) FROM expenses e WHERE e.custom_category_id = c.id) AS ever_count
                FROM custom_expense_categories c
                WHERE c.company_id = ? AND c.deleted_at IS NULL
                ORDER BY c.name COLLATE NOCASE, c.id
                """, arguments: [key])
            return try rows.map { row in
                let category = try CustomExpenseCategoryRecord(row: row).toDomain()
                let live: Int = row["live_count"]
                let ever: Int = row["ever_count"]
                return CustomCategoryUsage(category: category, liveExpenseCount: live, everUsed: ever > 0)
            }
        }
        return GRDBInsightsRepository.stream(observation, in: database.writer)
    }

    public func create(_ category: CustomExpenseCategory) async throws {
        let now = clock.now()
        try await database.writer.write { db in
            let existing = try Self.live(db, companyId: category.companyId.dbKey)
            var row = category
            row.name = try CustomCategoryRules.validatedName(category.name, excluding: nil, existing: existing)
            row.createdAt = now; row.updatedAt = now; row.deletedAt = nil
            try CustomExpenseCategoryRecord(row).insert(db)
        }
    }

    public func update(id: UUID, name: String, costGroup: CostGroup) async throws {
        let now = clock.now()
        try await database.writer.write { db in
            guard let record = try CustomExpenseCategoryRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { throw DomainError.notFound }
            let current = try record.toDomain()
            let everUsed = (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM expenses WHERE custom_category_id = ?", arguments: [record.id]) ?? 0) > 0
            var updated = try CustomCategoryRules.update(current, name: name, costGroup: costGroup, everUsed: everUsed, existing: try Self.live(db, companyId: record.companyId))
            guard updated.name != current.name || updated.costGroup != current.costGroup else { return }
            updated.updatedAt = now
            try CustomExpenseCategoryRecord(updated).update(db)
        }
    }

    public func softDelete(id: UUID) async throws {
        let stamp = Timestamps.string(clock.now())
        try await database.writer.write { db in
            guard let record = try CustomExpenseCategoryRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { throw DomainError.notFound }
            let live = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM expenses WHERE custom_category_id = ? AND deleted_at IS NULL", arguments: [record.id]) ?? 0
            try CustomCategoryRules.checkDelete(liveExpenseCount: live)
            try db.execute(sql: "UPDATE custom_expense_categories SET deleted_at = ?, updated_at = ?, sync_state = 'pending' WHERE id = ?", arguments: [stamp, stamp, record.id])
        }
    }

    static func live(_ db: Database, companyId: String) throws -> [CustomExpenseCategory] {
        try CustomExpenseCategoryRecord.filter(Column("company_id") == companyId && Column("deleted_at") == nil).fetchAll(db).map { try $0.toDomain() }
    }
}
