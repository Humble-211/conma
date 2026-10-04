// Packages/Data/Tests/DataTests/ReceiptStoreTests.swift
import XCTest
import GRDB
import Domain
@testable import Data

final class ReceiptStoreTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    var store: FileReceiptStore!

    override func setUp() { store = temporaryReceiptStore() }
    override func tearDown() { try? FileManager.default.removeItem(at: store.root) }

    func testWriteReadRemove() throws {
        let expenseId = UUID(), imageId = UUID()
        let bytes = Data([0xFF, 0xD8, 0x01, 0xFF, 0xD9])
        let path = try store.write(bytes, expenseId: expenseId, imageId: imageId)
        XCTAssertEqual(path, "Receipts/\(expenseId.uuidString.lowercased())/\(imageId.uuidString.lowercased()).jpg")
        XCTAssertEqual(try Data(contentsOf: store.url(for: path)), bytes)
        store.remove(relativePath: path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: path).path))
        store.remove(relativePath: path)                       // removing twice is a no-op
    }

    func testRecordsRoundTrip() async throws {
        let db = try AppDatabase.inMemory()
        let f = try await makeFixture(db, now: now)
        let category = CustomExpenseCategory(id: UUID(), companyId: f.companyId, name: "Scaffolding", costGroup: .equipment, createdAt: now, updatedAt: now, deletedAt: nil)
        let expense = Expense(id: UUID(), companyId: f.companyId, projectId: f.project.id, category: .custom, customCategoryId: category.id, costGroup: .equipment,
                              vendorName: "Sunbelt", amount: Money(Decimal(string: "40.00")!, .cad), tax: Money(Decimal(string: "5.20")!, .cad),
                              spentOn: CalendarDate(storage: "2026-10-01")!, paymentMethod: .cash, notes: "2 days", receiptImages: [], createdAt: now, updatedAt: now, deletedAt: nil)
        let page = ReceiptImage(id: UUID(), companyId: f.companyId, expenseId: expense.id, filePath: "Receipts/a/b.jpg", remotePath: nil, pageIndex: 0, createdAt: now, updatedAt: now, deletedAt: nil)
        let deletedPage = ReceiptImage(id: UUID(), companyId: f.companyId, expenseId: expense.id, filePath: "Receipts/a/c.jpg", remotePath: nil, pageIndex: 1, createdAt: now, updatedAt: now, deletedAt: now)
        try await db.writer.write { db in
            try CustomExpenseCategoryRecord(category).insert(db)
            try ExpenseRecord(expense).insert(db)
            try ReceiptImageRecord(page).insert(db)
            try ReceiptImageRecord(deletedPage).insert(db)
        }
        let companyKey = f.companyId.dbKey
        let (backCategory, byExpense, backExpense) = try await db.writer.read { db in
            (try CustomExpenseCategoryRecord.fetchOne(db, key: category.id.dbKey)?.toDomain(),
             try ReceiptImageRecord.fetchLive(db, companyId: companyKey),
             try ExpenseRecord.fetchOne(db, key: expense.id.dbKey)?.toDomain(currency: .cad, receipts: try ReceiptImageRecord.fetchLive(db, expenseId: expense.id.dbKey)))
        }
        XCTAssertEqual(backCategory, category)
        XCTAssertEqual(byExpense[expense.id.dbKey], [page])
        XCTAssertEqual(backExpense?.receiptImages, [page])
        XCTAssertEqual(backExpense?.customCategoryId, category.id)
        XCTAssertEqual(backExpense?.tax.storageString, "5.20")
    }
}
