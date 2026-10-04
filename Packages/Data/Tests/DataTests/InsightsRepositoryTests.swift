import XCTest
import GRDB
import Domain
@testable import Data

final class InsightsRepositoryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    var db: AppDatabase!
    var companyId: UUID!
    var project: Project!
    var customer: Customer!

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        let company = Company(id: UUID(), name: "N", currencyCode: .cad, createdAt: now, updatedAt: now, deletedAt: nil)
        let owner = User(id: UUID(), companyId: company.id, displayName: "Duc", email: nil, role: .owner, authUserId: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBCompanyRepository(database: db, clock: .fixed(now)).create(company: company, owner: owner)
        companyId = company.id
        customer = Customer(id: UUID(), companyId: companyId, name: "Ann", phone: nil, email: nil, preferredContact: nil, companyName: nil, secondaryContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBCustomerRepository(database: db, clock: .fixed(now)).save(customer)
        project = Project(id: UUID(), companyId: companyId, customerId: customer.id, name: "P", jobType: .kitchen, customJobType: nil, status: .inProgress, address: Address(line: "1", unit: nil, city: nil, region: nil, postalCode: nil), scopeDescription: nil, scopeFields: [], startDate: nil, estimatedCompletionDate: nil, workingDays: nil, hoursPerDay: nil, workersPerDay: nil, contractValue: Money(1000, .cad), manualProgress: nil, depositRequiredToStart: false, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBProjectRepository(database: db, clock: .fixed(now)).save(project, actor: ActivityActor(userId: owner.id, name: "Duc"))
    }

    func testObserveDashboardEmitsOnPaymentInsert() async throws {
        let repo = GRDBInsightsRepository(database: db)
        let stream = repo.observeDashboard(companyId: companyId)
        var iterator = stream.makeAsyncIterator()
        let first = try await iterator.next()!
        XCTAssertEqual(first.projects.count, 1)
        XCTAssertEqual(first.payments.count, 0)
        XCTAssertEqual(first.company.id, companyId)
        let pay = Payment(id: UUID(), companyId: companyId, projectId: project.id, scheduleItemId: nil, amount: Money(10, .cad), paidOn: CalendarDate(storage: "2026-10-01")!, method: .cash, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await db.writer.write { db in try PaymentRecord(pay).insert(db) }
        let second = try await iterator.next()!
        XCTAssertEqual(second.payments.map(\.id), [pay.id])
    }

    func testObserveProjectNilWhenDeleted() async throws {
        let repo = GRDBInsightsRepository(database: db)
        var iterator = repo.observeProject(id: project.id).makeAsyncIterator()
        let first = try await iterator.next()!
        XCTAssertEqual(first?.project.id, project.id)
        try await GRDBProjectRepository(database: db, clock: .fixed(now)).softDelete(id: project.id, actor: ActivityActor(userId: nil, name: "Duc"))
        let second = try await iterator.next()!
        XCTAssertNil(second)
    }

    func testObserveDashboardExcludesDeletedRows() async throws {
        let repo = GRDBInsightsRepository(database: db)
        let gone = Expense(id: UUID(), companyId: companyId, projectId: project.id, category: .materials, customCategoryId: nil, costGroup: .material, vendorName: nil, amount: Money(1, .cad), tax: .zero(.cad), spentOn: CalendarDate(storage: "2026-10-01")!, paymentMethod: nil, notes: nil, receiptImages: [], createdAt: now, updatedAt: now, deletedAt: now)
        try await db.writer.write { db in try ExpenseRecord(gone).insert(db) }
        var iterator = repo.observeDashboard(companyId: companyId).makeAsyncIterator()
        let first = try await iterator.next()!
        XCTAssertEqual(first.expenses.count, 0)
    }

    func testObserveProjectEmitsAfterExpenseCreate() async throws {
        let store = temporaryReceiptStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        var it = GRDBInsightsRepository(database: db).observeProject(id: project.id).makeAsyncIterator()
        let first = try await it.next()!
        XCTAssertEqual(first?.expenses.count, 0)
        let e = Expense(id: UUID(), companyId: companyId, projectId: project.id, category: .fuel, customCategoryId: nil, costGroup: .other, vendorName: nil,
                        amount: Money(250, .cad), tax: .zero(.cad), spentOn: CalendarDate(storage: "2026-10-03")!, paymentMethod: nil, notes: nil, receiptImages: [],
                        createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBExpenseRepository(database: db, clock: .fixed(now), receiptStore: store).create(e, receiptPages: [], actor: ActivityActor(userId: nil, name: "Duc"))
        let second = try await XCTUnwrapAsync(try await it.next()!)
        XCTAssertEqual(second.expenses.map(\.id), [e.id])
        XCTAssertEqual(ProjectInsightsComposer.compose(second.with(today: CalendarDate(storage: "2026-10-03")!)).financials?.spentSoFar, Money(250, .cad))
    }

    func testObserveDashboardMissingCompanyThrowsDomainNotFound() async throws {
        var it = GRDBInsightsRepository(database: db).observeDashboard(companyId: UUID()).makeAsyncIterator()
        do { _ = try await it.next(); XCTFail("expected error") } catch { XCTAssertEqual(error as? DomainError, .notFound) }
    }
}
