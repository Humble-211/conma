// Packages/Data/Tests/DataTests/PaymentRepositoryTests.swift
import XCTest
import GRDB
import Domain
@testable import Data

final class PaymentRepositoryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let today = CalendarDate(storage: "2026-10-03")!
    var db: AppDatabase!
    var f: Fixture!
    var repo: GRDBPaymentRepository!
    var deposit: PaymentScheduleItem!
    var balance: PaymentScheduleItem!

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        f = try await makeFixture(db, now: now)
        repo = GRDBPaymentRepository(database: db, clock: .fixed(now))
        deposit = item("Deposit", 400, order: 0)
        balance = item("schedule.row.final", 600, order: 1)
        try await GRDBPaymentScheduleRepository(database: db, clock: .fixed(now)).replace(projectId: f.project.id, change: ScheduleItemChange(
            upserts: [deposit, balance], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(1000, .cad)), actor: f.actor)
    }

    func item(_ label: String, _ amount: Int, order: Int, project: Project? = nil) -> PaymentScheduleItem {
        PaymentScheduleItem(id: UUID(), companyId: f.companyId, projectId: (project ?? f.project).id, label: label, amount: Money(Decimal(amount), .cad),
                            percentage: nil, dueDate: CalendarDate(storage: "2026-10-10"), triggerText: nil, isDeposit: order == 0, notes: nil,
                            sortOrder: order, createdAt: now, updatedAt: now, deletedAt: nil)
    }
    func payment(_ amount: String, item: UUID?, method: PaymentMethod = .eTransfer, currency: CurrencyCode = .cad, project: Project? = nil) -> Payment {
        Payment(id: UUID(), companyId: f.companyId, projectId: (project ?? f.project).id, scheduleItemId: item, amount: Money(storage: amount, currency: currency)!,
                paidOn: today, method: method, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
    }
    func activities() async throws -> [(action: String, details: String)] {
        try await db.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT action, details_json FROM activity_log WHERE entity_type = 'payment' ORDER BY rowid").map { ($0["action"], $0["details_json"]) }
        }
    }
    func paymentRows() async throws -> Int {
        try await db.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM payments") ?? 0 }
    }
    func insights() async throws -> ProjectInsights {
        var it = GRDBInsightsRepository(database: db).observeProject(id: f.project.id).makeAsyncIterator()
        let value = try await it.next()
        let snap = try XCTUnwrap(value ?? nil)
        return ProjectInsightsComposer.compose(snap.with(today: today))
    }
    func otherProject() async throws -> Project {
        let p = f.project
        let q = Project(id: UUID(), companyId: p.companyId, customerId: p.customerId, name: "Q", jobType: p.jobType, customJobType: nil, status: .inProgress, address: p.address,
                        scopeDescription: nil, scopeFields: [], startDate: nil, estimatedCompletionDate: nil, workingDays: nil, hoursPerDay: nil, workersPerDay: nil,
                        contractValue: Money(500, .cad), manualProgress: nil, depositRequiredToStart: false, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBProjectRepository(database: db, clock: .fixed(now)).save(q, actor: f.actor)
        return q
    }

    func testCreateLinkedPaymentLogsActivityAndPaysItem() async throws {
        let p = payment("400.00", item: deposit.id)
        try await repo.create(p, actor: f.actor)
        let back = try await XCTUnwrapAsync(try await repo.get(id: p.id))
        XCTAssertEqual(back.amount.storageString, "400.00")
        XCTAssertEqual(back.scheduleItemId, deposit.id)
        let a = try await activities()
        XCTAssertEqual(a.map(\.action), ["paymentReceived"])
        XCTAssertEqual(a[0].details, #"{"amount":"400.00","currency":"CAD","item":"Deposit","method":"eTransfer"}"#)
        let i = try await insights()
        XCTAssertEqual(i.payments.map(\.status), [.paid, .upcoming])
        XCTAssertEqual(i.financials?.collected, Money(400, .cad))
        XCTAssertEqual(i.financials?.outstandingBalance, Money(600, .cad))
    }

    func testOverpaymentAndUnlinkedPayment() async throws {
        try await repo.create(payment("700.00", item: balance.id), actor: f.actor)
        try await repo.create(payment("50.00", item: nil), actor: f.actor)
        let i = try await insights()
        XCTAssertEqual(i.payments.map(\.status), [.upcoming, .paid])
        XCTAssertEqual(i.payments.map(\.remaining.storageString), ["400.00", "0.00"])
        XCTAssertEqual(i.payments[0].paid, Money(0, .cad))               // the 100 extra never moves to the deposit
        XCTAssertEqual(i.financials?.collected, Money(750, .cad))
        XCTAssertEqual(i.unallocatedCollected, Money(50, .cad))
        let a = try await activities()
        XCTAssertEqual(a.last?.details, #"{"amount":"50.00","currency":"CAD","item":"","method":"eTransfer"}"#)
    }

    func testRefusesDeletedOrForeignItemAndWritesNothing() async throws {
        let q = try await otherProject()
        let foreign = item("Q deposit", 100, order: 0, project: q)
        try await GRDBPaymentScheduleRepository(database: db, clock: .fixed(now)).replace(projectId: q.id, change: ScheduleItemChange(
            upserts: [foreign], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(100, .cad)), actor: f.actor)
        await XCTAssertThrowsErrorAsync(try await self.repo.create(self.payment("10.00", item: foreign.id), actor: self.f.actor)) { XCTAssertEqual($0 as? DomainError, .notFound) }
        try await GRDBPaymentScheduleRepository(database: db, clock: .fixed(now)).replace(projectId: f.project.id, change: ScheduleItemChange(
            upserts: [], deletedIds: [deposit.id], totalBefore: Money(1000, .cad), totalAfter: Money(600, .cad)), actor: f.actor)
        await XCTAssertThrowsErrorAsync(try await self.repo.create(self.payment("10.00", item: self.deposit.id), actor: self.f.actor)) { XCTAssertEqual($0 as? DomainError, .notFound) }
        await XCTAssertThrowsErrorAsync(try await self.repo.create(self.payment("10.00", item: nil, currency: .usd), actor: self.f.actor)) { XCTAssertEqual($0 as? DomainError, .currencyMismatch) }
        let zero = Payment(id: UUID(), companyId: f.companyId, projectId: f.project.id, scheduleItemId: nil, amount: .zero(.cad), paidOn: today, method: .cash,
                           notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        await XCTAssertThrowsErrorAsync(try await self.repo.create(zero, actor: self.f.actor)) { XCTAssertEqual($0 as? DomainError, .invalidPaymentAmount) }
        try await GRDBProjectRepository(database: db, clock: .fixed(now)).softDelete(id: q.id, actor: f.actor)
        await XCTAssertThrowsErrorAsync(try await self.repo.create(self.payment("10.00", item: nil, project: q), actor: self.f.actor)) { XCTAssertEqual($0 as? DomainError, .notFound) }
        await XCTAssertEqualAsync(try await self.paymentRows(), 0)
        await XCTAssertEqualAsync(try await self.activities().count, 0)
    }

    func testUpdateWithoutAmountChangeOmitsFrom() async throws {
        let p = payment("400.00", item: deposit.id)
        try await repo.create(p, actor: f.actor)
        var changed = try await XCTUnwrapAsync(try await repo.get(id: p.id))
        changed.method = .cash
        changed.scheduleItemId = nil
        try await GRDBPaymentRepository(database: db, clock: .fixed(now.addingTimeInterval(60))).update(changed, actor: f.actor)
        let a = try await activities()
        XCTAssertEqual(a.map(\.action), ["paymentReceived", "paymentUpdated"])
        XCTAssertEqual(a[1].details, #"{"amount":"400.00","currency":"CAD","item":"","method":"cash"}"#)
    }

    func testUpdateNoOpAmountChangeAndScope() async throws {
        let p = payment("400.00", item: deposit.id)
        try await repo.create(p, actor: f.actor)
        let stored = try await XCTUnwrapAsync(try await repo.get(id: p.id))
        let later = GRDBPaymentRepository(database: db, clock: .fixed(now.addingTimeInterval(60)))
        try await later.update(stored, actor: f.actor)                                    // nothing changed
        await XCTAssertEqualAsync(try await self.activities().map(\.action), ["paymentReceived"])
        await XCTAssertEqualAsync(try await self.repo.get(id: p.id)?.updatedAt, now)
        var changed = stored
        changed.amount = Money(450, .cad)
        changed.scheduleItemId = nil
        try await later.update(changed, actor: f.actor)
        let a = try await activities()
        XCTAssertEqual(a.map(\.action), ["paymentReceived", "paymentUpdated"])
        XCTAssertEqual(a[1].details, #"{"amount":"450.00","currency":"CAD","from":"400.00","item":"","method":"eTransfer"}"#)
        let back = try await XCTUnwrapAsync(try await repo.get(id: p.id))
        XCTAssertNil(back.scheduleItemId)
        XCTAssertEqual(back.updatedAt, now.addingTimeInterval(60))
        XCTAssertEqual(back.createdAt, now)
        let q = try await otherProject()
        let moved = Payment(id: p.id, companyId: f.companyId, projectId: q.id, scheduleItemId: nil, amount: Money(450, .cad), paidOn: today, method: .eTransfer,
                            notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        await XCTAssertThrowsErrorAsync(try await self.repo.update(moved, actor: self.f.actor)) { XCTAssertEqual($0 as? DataError, .scopeMismatch) }
    }

    func testSoftDeleteRemovesFromCollected() async throws {
        let p = payment("400.00", item: deposit.id)
        try await repo.create(p, actor: f.actor)
        try await repo.softDelete(id: p.id, actor: f.actor)
        await XCTAssertNilAsync(try await self.repo.get(id: p.id))
        let i = try await insights()
        XCTAssertEqual(i.financials?.collected, Money(0, .cad))
        XCTAssertEqual(i.payments.first?.status, .upcoming)
        let a = try await activities()
        XCTAssertEqual(a.map(\.action), ["paymentReceived", "paymentDeleted"])
        XCTAssertEqual(a[1].details, #"{"amount":"400.00","currency":"CAD","item":"Deposit","method":"eTransfer"}"#)
        await XCTAssertThrowsErrorAsync(try await self.repo.softDelete(id: p.id, actor: self.f.actor)) { XCTAssertEqual($0 as? DomainError, .notFound) }
    }

    func testLastUsedMethod() async throws {
        await XCTAssertNilAsync(try await self.repo.lastUsedMethod(companyId: self.f.companyId))
        try await repo.create(payment("10.00", item: nil, method: .cheque), actor: f.actor)
        let cash = payment("20.00", item: nil, method: .cash)
        try await GRDBPaymentRepository(database: db, clock: .fixed(now.addingTimeInterval(60))).create(cash, actor: f.actor)
        await XCTAssertEqualAsync(try await self.repo.lastUsedMethod(companyId: self.f.companyId), .cash)
        try await repo.softDelete(id: cash.id, actor: f.actor)
        await XCTAssertEqualAsync(try await self.repo.lastUsedMethod(companyId: self.f.companyId), .cheque)
    }
}
