// Packages/Data/Tests/DataTests/CustomCategoryRepositoryTests.swift
import XCTest
import GRDB
import Domain
@testable import Data

final class CustomCategoryRepositoryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    var db: AppDatabase!
    var f: Fixture!
    var store: FileReceiptStore!
    var repo: GRDBCustomCategoryRepository!
    var expenses: GRDBExpenseRepository!

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        f = try await makeFixture(db, now: now)
        store = temporaryReceiptStore()
        repo = GRDBCustomCategoryRepository(database: db, clock: .fixed(now))
        expenses = GRDBExpenseRepository(database: db, clock: .fixed(now), receiptStore: store)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: store.root) }

    func category(_ name: String, _ group: CostGroup = .equipment) -> CustomExpenseCategory {
        CustomExpenseCategory(id: UUID(), companyId: f.companyId, name: name, costGroup: group, createdAt: now, updatedAt: now, deletedAt: nil)
    }
    func useIn(_ c: CustomExpenseCategory) async throws -> UUID {
        let e = Expense(id: UUID(), companyId: f.companyId, projectId: f.project.id, category: .custom, customCategoryId: c.id, costGroup: c.costGroup, vendorName: nil,
                        amount: Money(40, .cad), tax: .zero(.cad), spentOn: CalendarDate(storage: "2026-10-01")!, paymentMethod: nil, notes: nil, receiptImages: [],
                        createdAt: now, updatedAt: now, deletedAt: nil)
        try await expenses.create(e, receiptPages: [], actor: f.actor)
        return e.id
    }

    func testCreateTrimsAndRejectsDuplicates() async throws {
        try await repo.create(category("  Scaffolding "))
        await XCTAssertThrowsErrorAsync(try await self.repo.create(self.category("scaffolding"))) { XCTAssertEqual($0 as? DomainError, .duplicateName) }
        await XCTAssertThrowsErrorAsync(try await self.repo.create(self.category("   "))) { XCTAssertEqual($0 as? DomainError, .emptyName) }
        var it = repo.observeAll(companyId: f.companyId).makeAsyncIterator()
        let usage = try await it.next()!
        XCTAssertEqual(usage.map(\.category.name), ["Scaffolding"])
        XCTAssertEqual(usage.first?.liveExpenseCount, 0)
        XCTAssertEqual(usage.first?.everUsed, false)
    }

    /// Foundation §5.2 rule deferred by 2a/2b: the group is immutable once ANY expense (even a deleted one) used the category.
    func testGroupLockedOnceUsedEvenIfExpenseDeleted() async throws {
        let c = category("Scaffolding")
        try await repo.create(c)
        let expenseId = try await useIn(c)
        try await expenses.softDelete(id: expenseId, actor: f.actor)
        await XCTAssertThrowsErrorAsync(try await self.repo.update(id: c.id, name: "Scaffolding", costGroup: .other)) { XCTAssertEqual($0 as? DomainError, .categoryInUse) }
        try await repo.update(id: c.id, name: "Scaffold", costGroup: .equipment)
        var it = repo.observeAll(companyId: f.companyId).makeAsyncIterator()
        let usage = try await it.next()!
        XCTAssertEqual(usage.first?.category.name, "Scaffold")
        XCTAssertEqual(usage.first?.category.costGroup, .equipment)
        XCTAssertEqual(usage.first?.liveExpenseCount, 0)
        XCTAssertEqual(usage.first?.everUsed, true)
    }

    func testUnusedCategoryGroupChangeAllowed() async throws {
        let c = category("Scaffolding")
        try await repo.create(c)
        try await repo.update(id: c.id, name: "Scaffolding", costGroup: .material)
        var it = repo.observeAll(companyId: f.companyId).makeAsyncIterator()
        XCTAssertEqual(try await it.next()!.first?.category.costGroup, .material)
        await XCTAssertThrowsErrorAsync(try await self.repo.update(id: UUID(), name: "X", costGroup: .other)) { XCTAssertEqual($0 as? DomainError, .notFound) }
    }

    func testDeleteBlockedWhileLiveExpense() async throws {
        let c = category("Scaffolding")
        try await repo.create(c)
        let expenseId = try await useIn(c)
        await XCTAssertThrowsErrorAsync(try await self.repo.softDelete(id: c.id)) { XCTAssertEqual($0 as? DomainError, .categoryHasExpenses) }
        try await expenses.softDelete(id: expenseId, actor: f.actor)
        try await repo.softDelete(id: c.id)
        var it = repo.observeAll(companyId: f.companyId).makeAsyncIterator()
        XCTAssertEqual(try await it.next()!.count, 0)
        try await repo.create(category("Scaffolding"))                     // name reusable after delete (partial unique index)
    }
}
