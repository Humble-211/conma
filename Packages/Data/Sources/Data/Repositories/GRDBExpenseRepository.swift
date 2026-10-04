// Packages/Data/Sources/Data/Repositories/GRDBExpenseRepository.swift
import Foundation
import GRDB
import Domain

public final class GRDBExpenseRepository: ExpenseRepository {
    private let database: AppDatabase
    private let clock: Clock
    private let receiptStore: FileReceiptStore

    public init(database: AppDatabase, clock: Clock, receiptStore: FileReceiptStore) {
        self.database = database; self.clock = clock; self.receiptStore = receiptStore
    }

    // MARK: Reads

    public func observeAll(companyId: UUID) -> AsyncThrowingStream<ExpenseListSnapshot, Error> {
        let key = companyId.dbKey
        let observation = ValueObservation.tracking { db -> ExpenseListSnapshot in
            let currency = try GRDBProjectRepository.currency(db, companyId: key)
            let projects = try ProjectRecord.filter(Column("company_id") == key && Column("deleted_at") == nil).fetchAll(db)
                .map { try $0.toDomain(currency: currency, scopeFields: []) }
            let receipts = try ReceiptImageRecord.fetchLive(db, companyId: key)
            let expenses = try ExpenseRecord.filter(Column("company_id") == key && Column("deleted_at") == nil)
                .order(Column("spent_on").desc, Column("created_at").desc).fetchAll(db)
                .map { try $0.toDomain(currency: currency, receipts: receipts[$0.id] ?? []) }
            let categories = try CustomExpenseCategoryRecord.filter(Column("company_id") == key).order(Column("name")).fetchAll(db).map { try $0.toDomain() }
            return ExpenseListSnapshot(currency: currency, expenses: expenses, projects: projects, customCategories: categories)
        }
        return GRDBInsightsRepository.stream(observation, in: database.writer)
    }

    public func get(id: UUID) async throws -> Expense? {
        try await database.writer.read { db in
            guard let record = try ExpenseRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { return nil }
            let currency = try GRDBProjectRepository.currency(db, companyId: record.companyId)
            return try record.toDomain(currency: currency, receipts: try ReceiptImageRecord.fetchLive(db, expenseId: record.id))
        }
    }

    public func fileURL(for image: ReceiptImage) -> URL { receiptStore.url(for: image.filePath) }

    // MARK: Writes

    public func create(_ expense: Expense, receiptPages: [Data], actor: ActivityActor) async throws {
        try expense.validate()
        try ReceiptRules.validate(pageCount: receiptPages.count)
        let now = clock.now()
        let written = try writeFiles(receiptPages, expense: expense, firstIndex: 0, now: now)
        var stamped = expense
        stamped.createdAt = now; stamped.updatedAt = now; stamped.deletedAt = nil; stamped.receiptImages = []
        let input = stamped
        do {
            try await database.writer.write { db in
                let currency = try GRDBProjectRepository.currency(db, companyId: input.companyId.dbKey)
                guard input.amount.currency == currency, input.tax.currency == currency else { throw DomainError.currencyMismatch }
                try Self.requireLiveProject(db, id: input.projectId, companyId: input.companyId)
                var row = input
                row.costGroup = try Self.snapshotGroup(db, for: input)
                try ExpenseRecord(row).insert(db)
                for image in written { try ReceiptImageRecord(image).insert(db) }
                try ActivityLogRecord.append(db, companyId: row.companyId, actor: actor, action: .expenseAdded, entityType: "expense", entityId: row.id,
                                             projectId: row.projectId, details: try Self.details(db, row), at: now)
            }
        } catch {
            for image in written { receiptStore.remove(relativePath: image.filePath) }
            throw error
        }
    }

    public func update(_ expense: Expense, receipts: ReceiptChange, actor: ActivityActor) async throws {
        try expense.validate()
        try ReceiptRules.validate(pageCount: receipts.keptImageIds.count + receipts.newPages.count)
        let now = clock.now()
        let stamp = Timestamps.string(now)
        let added = try writeFiles(receipts.newPages, expense: expense, firstIndex: receipts.keptImageIds.count, now: now)
        let input = expense
        let keep = receipts.keptImageIds.map(\.dbKey)
        do {
            try await database.writer.write { db in
                guard let old = try ExpenseRecord.filter(Column("id") == input.id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { throw DomainError.notFound }
                let currency = try GRDBProjectRepository.currency(db, companyId: old.companyId)
                guard input.amount.currency == currency, input.tax.currency == currency else { throw DomainError.currencyMismatch }
                try Self.requireLiveProject(db, id: input.projectId, companyId: input.companyId)
                let previous = try old.toDomain(currency: currency)
                let liveImages = try ReceiptImageRecord.filter(Column("expense_id") == old.id && Column("deleted_at") == nil).order(Column("page_index")).fetchAll(db)
                let liveIds = liveImages.map(\.id)
                guard Set(keep).isSubset(of: Set(liveIds)) else { throw DomainError.notFound }

                var row = input
                row.createdAt = previous.createdAt
                row.updatedAt = previous.updatedAt
                row.deletedAt = nil
                if ExpenseCategoryChoice(previous) == ExpenseCategoryChoice(input) {
                    row.costGroup = previous.costGroup
                } else {
                    row.costGroup = try Self.snapshotGroup(db, for: input)
                }
                var candidate = ExpenseRecord(row)
                candidate.syncState = old.syncState
                let pagesChanged = keep != liveIds || !added.isEmpty
                guard candidate != old || pagesChanged else { return }

                row.updatedAt = now
                try ExpenseRecord(row).update(db)
                if keep != liveIds {
                    for image in liveImages where !keep.contains(image.id) {
                        try db.execute(sql: "UPDATE receipt_images SET deleted_at = ?, updated_at = ?, sync_state = 'pending' WHERE id = ?", arguments: [stamp, stamp, image.id])
                    }
                    // Two passes keep the partial unique index (expense_id, page_index) satisfied while renumbering.
                    for (index, id) in keep.enumerated() {
                        try db.execute(sql: "UPDATE receipt_images SET page_index = ?, updated_at = ?, sync_state = 'pending' WHERE id = ?", arguments: [1000 + index, stamp, id])
                    }
                    for (index, id) in keep.enumerated() {
                        try db.execute(sql: "UPDATE receipt_images SET page_index = ? WHERE id = ?", arguments: [index, id])
                    }
                }
                for image in added { try ReceiptImageRecord(image).insert(db) }
                var details = try Self.details(db, row)
                details["from"] = try previous.totalCost().storageString
                if previous.projectId != row.projectId { details["fromProjectId"] = previous.projectId.dbKey }
                try ActivityLogRecord.append(db, companyId: row.companyId, actor: actor, action: .expenseUpdated, entityType: "expense", entityId: row.id,
                                             projectId: row.projectId, details: details, at: now)
            }
        } catch {
            for image in added { receiptStore.remove(relativePath: image.filePath) }
            throw error
        }
    }

    public func softDelete(id: UUID, actor: ActivityActor) async throws {
        let now = clock.now()
        let stamp = Timestamps.string(now)
        try await database.writer.write { db in
            guard let record = try ExpenseRecord.filter(Column("id") == id.dbKey && Column("deleted_at") == nil).fetchOne(db) else { throw DomainError.notFound }
            let currency = try GRDBProjectRepository.currency(db, companyId: record.companyId)
            let expense = try record.toDomain(currency: currency)
            let set = "SET deleted_at = ?, updated_at = ?, sync_state = 'pending'"
            try db.execute(sql: "UPDATE expenses \(set) WHERE id = ?", arguments: [stamp, stamp, record.id])
            try db.execute(sql: "UPDATE receipt_images \(set) WHERE expense_id = ? AND deleted_at IS NULL", arguments: [stamp, stamp, record.id])
            try ActivityLogRecord.append(db, companyId: expense.companyId, actor: actor, action: .expenseDeleted, entityType: "expense", entityId: expense.id,
                                         projectId: expense.projectId, details: try Self.details(db, expense), at: now)
        }
    }

    // MARK: Helpers

    /// Writes JPEG pages before the transaction; on a partial failure removes what it already wrote.
    private func writeFiles(_ pages: [Data], expense: Expense, firstIndex: Int, now: Date) throws -> [ReceiptImage] {
        var images: [ReceiptImage] = []
        do {
            for (offset, page) in pages.enumerated() {
                let imageId = UUID()
                let path = try receiptStore.write(page, expenseId: expense.id, imageId: imageId)
                images.append(ReceiptImage(id: imageId, companyId: expense.companyId, expenseId: expense.id, filePath: path, remotePath: nil,
                                           pageIndex: firstIndex + offset, createdAt: now, updatedAt: now, deletedAt: nil))
            }
        } catch {
            for image in images { receiptStore.remove(relativePath: image.filePath) }
            throw error
        }
        return images
    }

    static func requireLiveProject(_ db: Database, id: UUID, companyId: UUID) throws {
        let live = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM projects WHERE id = ? AND company_id = ? AND deleted_at IS NULL",
                                    arguments: [id.dbKey, companyId.dbKey]) ?? 0
        guard live > 0 else { throw DomainError.notFound }
    }

    /// Data is authoritative for the snapshot (spec §2): built-ins use the Foundation mapping (checked by `validate()`),
    /// custom categories their current group; a missing or deleted custom category is `notFound`.
    static func snapshotGroup(_ db: Database, for expense: Expense) throws -> CostGroup {
        guard expense.category == .custom else { return expense.costGroup }
        guard let id = expense.customCategoryId,
              let record = try CustomExpenseCategoryRecord.filter(Column("id") == id.dbKey && Column("company_id") == expense.companyId.dbKey && Column("deleted_at") == nil).fetchOne(db)
        else { throw DomainError.notFound }
        return try record.toDomain().costGroup
    }

    static func details(_ db: Database, _ expense: Expense) throws -> [String: String] {
        let name = try expense.customCategoryId.flatMap { try String.fetchOne(db, sql: "SELECT name FROM custom_expense_categories WHERE id = ?", arguments: [$0.dbKey]) } ?? ""
        return ["category": expense.category.rawValue, "categoryName": name, "total": try expense.totalCost().storageString, "vendor": expense.vendorName ?? ""]
    }
}
