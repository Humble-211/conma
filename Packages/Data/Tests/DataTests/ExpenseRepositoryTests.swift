// Packages/Data/Tests/DataTests/ExpenseRepositoryTests.swift
import XCTest
import GRDB
import Domain
@testable import Data

final class ExpenseRepositoryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
    var db: AppDatabase!
    var f: Fixture!
    var store: FileReceiptStore!
    var repo: GRDBExpenseRepository!

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        f = try await makeFixture(db, now: now)
        store = temporaryReceiptStore()
        repo = GRDBExpenseRepository(database: db, clock: .fixed(now), receiptStore: store)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: store.root) }

    func expense(_ category: ExpenseCategory = .materials, group: CostGroup = .material, amount: Int = 100, tax: Int = 13, custom: UUID? = nil, currency: CurrencyCode = .cad) -> Expense {
        Expense(id: UUID(), companyId: f.companyId, projectId: f.project.id, category: category, customCategoryId: custom, costGroup: group, vendorName: "Home Depot",
                amount: Money(Decimal(amount), currency), tax: Money(Decimal(tax), currency), spentOn: CalendarDate(storage: "2026-10-01")!, paymentMethod: .creditCard,
                notes: nil, receiptImages: [], createdAt: now, updatedAt: now, deletedAt: nil)
    }
    func activities() async throws -> [(action: String, details: String)] {
        try await db.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT action, details_json FROM activity_log WHERE entity_type = 'expense' ORDER BY rowid").map { ($0["action"], $0["details_json"]) }
        }
    }
    func scaffolding(_ group: CostGroup = .equipment) async throws -> CustomExpenseCategory {
        let c = CustomExpenseCategory(id: UUID(), companyId: f.companyId, name: "Scaffolding", costGroup: group, createdAt: now, updatedAt: now, deletedAt: nil)
        try await db.writer.write { db in try CustomExpenseCategoryRecord(c).insert(db) }   // the category repository arrives in Task 7
        return c
    }
    func jpgFiles(_ expenseId: UUID) -> [String] {
        let dir = store.root.appendingPathComponent("Receipts/\(expenseId.uuidString.lowercased())", isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".jpg") }
    }

    func testCreateWritesExpenseReceiptsAndActivity() async throws {
        let e = expense()
        try await repo.create(e, receiptPages: [jpeg, jpeg], actor: f.actor)
        let back = try await XCTUnwrapAsync(try await repo.get(id: e.id))
        XCTAssertEqual(back.receiptImages.map(\.pageIndex), [0, 1])
        let first = try XCTUnwrap(back.receiptImages.first)
        XCTAssertEqual(first.filePath, "Receipts/\(e.id.uuidString.lowercased())/\(first.id.uuidString.lowercased()).jpg")
        XCTAssertEqual(try Data(contentsOf: repo.fileURL(for: first)), jpeg)
        XCTAssertEqual(back.amount.storageString, "100.00")
        let a = try await activities()
        XCTAssertEqual(a.map(\.action), ["expenseAdded"])
        XCTAssertEqual(a[0].details, #"{"category":"materials","categoryName":"","total":"113.00","vendor":"Home Depot"}"#)
    }

    func testCustomCategoryGroupComesFromDatabase() async throws {
        let c = try await scaffolding(.equipment)
        let e = expense(.custom, group: .other, custom: c.id)            // stale group in the entity
        try await repo.create(e, receiptPages: [], actor: f.actor)
        await XCTAssertEqualAsync(try await repo.get(id: e.id)?.costGroup, .equipment)
        await XCTAssertEqualAsync(try await activities().last?.details, #"{"category":"custom","categoryName":"Scaffolding","total":"113.00","vendor":"Home Depot"}"#)
    }

    func testCreateOnDeletedProjectThrowsAndLeavesNoFiles() async throws {
        try await GRDBProjectRepository(database: db, clock: .fixed(now)).softDelete(id: f.project.id, actor: f.actor)
        let e = expense()
        await XCTAssertThrowsErrorAsync(try await repo.create(e, receiptPages: [jpeg, jpeg], actor: f.actor)) { XCTAssertEqual($0 as? DomainError, .notFound) }
        XCTAssertEqual(jpgFiles(e.id), [])
        let rows = try await db.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM expenses") ?? -1 }
        XCTAssertEqual(rows, 0)
        await XCTAssertEqualAsync(try await activities().count, 0)
    }

    func testCurrencyMismatchAndTooManyPagesRejected() async throws {
        await XCTAssertThrowsErrorAsync(try await repo.create(expense(currency: .usd), receiptPages: [], actor: f.actor)) { XCTAssertEqual($0 as? DomainError, .currencyMismatch) }
        await XCTAssertThrowsErrorAsync(try await repo.create(expense(), receiptPages: Array(repeating: jpeg, count: 11), actor: f.actor)) { XCTAssertEqual($0 as? DomainError, .tooManyReceiptPages) }
        let rows = try await db.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM expenses") ?? -1 }
        XCTAssertEqual(rows, 0)
    }

    func testUpdateRemovesAndAddsPages() async throws {
        let e = expense()
        try await repo.create(e, receiptPages: [jpeg, jpeg], actor: f.actor)
        let created = try await XCTUnwrapAsync(try await repo.get(id: e.id))
        let p0 = created.receiptImages[0], p1 = created.receiptImages[1]
        try await repo.update(created, receipts: ReceiptChange(keptImageIds: [p1.id], newPages: [jpeg]), actor: f.actor)
        let back = try await XCTUnwrapAsync(try await repo.get(id: e.id))
        XCTAssertEqual(back.receiptImages.map(\.pageIndex), [0, 1])
        XCTAssertEqual(back.receiptImages.first?.id, p1.id)
        let p0Deleted = try await db.writer.read { db in try String.fetchOne(db, sql: "SELECT deleted_at FROM receipt_images WHERE id = ?", arguments: [p0.id.dbKey]) }
        XCTAssertNotNil(p0Deleted)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo.fileURL(for: p0).path))   // file kept
        XCTAssertEqual(jpgFiles(e.id).count, 3)
        await XCTAssertEqualAsync(try await activities().map(\.action), ["expenseAdded", "expenseUpdated"])
    }

    func testNoOpUpdateWritesNothing() async throws {
        let e = expense()
        try await repo.create(e, receiptPages: [jpeg], actor: f.actor)
        let created = try await XCTUnwrapAsync(try await repo.get(id: e.id))
        try await repo.update(created, receipts: ReceiptChange(keptImageIds: created.receiptImages.map(\.id), newPages: []), actor: f.actor)
        await XCTAssertEqualAsync(try await activities().count, 1)
    }

    func testAmountChangeLogsFromAndTotal() async throws {
        let e = expense()
        try await repo.create(e, receiptPages: [], actor: f.actor)
        var changed = try await XCTUnwrapAsync(try await repo.get(id: e.id))
        changed.amount = Money(150, .cad)
        try await repo.update(changed, receipts: ReceiptChange(keptImageIds: [], newPages: []), actor: f.actor)
        await XCTAssertEqualAsync(try await repo.get(id: e.id)?.amount.storageString, "150.00")
        await XCTAssertEqualAsync(try await activities().last?.details, #"{"category":"materials","categoryName":"","from":"113.00","total":"163.00","vendor":"Home Depot"}"#)
    }

    func testKeepingCategoryKeepsSnapshotGroup() async throws {
        let c = try await scaffolding(.equipment)
        let e = expense(.custom, group: .equipment, custom: c.id)
        try await repo.create(e, receiptPages: [], actor: f.actor)
        try await db.writer.write { db in try db.execute(sql: "UPDATE custom_expense_categories SET cost_group = 'other' WHERE id = ?", arguments: [c.id.dbKey]) }
        var changed = try await XCTUnwrapAsync(try await repo.get(id: e.id))
        changed.amount = Money(120, .cad)
        try await repo.update(changed, receipts: ReceiptChange(keptImageIds: [], newPages: []), actor: f.actor)
        await XCTAssertEqualAsync(try await repo.get(id: e.id)?.costGroup, .equipment)
    }

    func testUpdateMissingOrForeignPageThrows() async throws {
        let e = expense()
        try await repo.create(e, receiptPages: [], actor: f.actor)
        let created = try await XCTUnwrapAsync(try await repo.get(id: e.id))
        await XCTAssertThrowsErrorAsync(try await repo.update(created, receipts: ReceiptChange(keptImageIds: [UUID()], newPages: []), actor: f.actor)) { XCTAssertEqual($0 as? DomainError, .notFound) }
        try await repo.softDelete(id: e.id, actor: f.actor)
        await XCTAssertThrowsErrorAsync(try await repo.update(created, receipts: ReceiptChange(keptImageIds: [], newPages: [self.jpeg]), actor: f.actor)) { XCTAssertEqual($0 as? DomainError, .notFound) }
        XCTAssertEqual(jpgFiles(e.id).count, 0)                                           // rolled-back page removed
    }

    func testSoftDeleteKeepsFilesAndEmits() async throws {
        let e = expense()
        try await repo.create(e, receiptPages: [jpeg], actor: f.actor)
        var it = repo.observeAll(companyId: f.companyId).makeAsyncIterator()
        let first = try await it.next()!
        XCTAssertEqual(first.expenses.map(\.id), [e.id])
        XCTAssertEqual(first.expenses.first?.receiptImages.count, 1)
        XCTAssertEqual(first.projects.map(\.id), [f.project.id])
        XCTAssertEqual(first.currency, .cad)
        try await repo.softDelete(id: e.id, actor: f.actor)
        let second = try await it.next()!
        XCTAssertEqual(second.expenses.count, 0)
        let liveReceipts = try await db.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM receipt_images WHERE deleted_at IS NULL") ?? -1 }
        XCTAssertEqual(liveReceipts, 0)
        XCTAssertEqual(jpgFiles(e.id).count, 1)
        await XCTAssertNilAsync(try await repo.get(id: e.id))
        await XCTAssertEqualAsync(try await activities().map(\.action), ["expenseAdded", "expenseDeleted"])
        await XCTAssertThrowsErrorAsync(try await repo.softDelete(id: e.id, actor: f.actor)) { XCTAssertEqual($0 as? DomainError, .notFound) }
    }
}
