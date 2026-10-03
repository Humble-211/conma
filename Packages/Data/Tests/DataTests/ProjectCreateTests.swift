import XCTest
import GRDB
import Domain
@testable import Data

final class ProjectCreateTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    var db: AppDatabase!; var companyId: UUID!; var actor: ActivityActor!; var repo: GRDBProjectRepository!; var customerId: UUID!

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        let company = Company(id: UUID(), name: "N", currencyCode: .cad, createdAt: now, updatedAt: now, deletedAt: nil)
        let owner = User(id: UUID(), companyId: company.id, displayName: "Duc", email: nil, role: .owner, authUserId: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBCompanyRepository(database: db, clock: .fixed(now)).create(company: company, owner: owner)
        companyId = company.id; actor = ActivityActor(userId: owner.id, name: "Duc")
        let c = Customer(id: UUID(), companyId: companyId, name: "Ann", phone: nil, email: nil, preferredContact: nil, companyName: nil, secondaryContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBCustomerRepository(database: db, clock: .fixed(now)).save(c)
        customerId = c.id
        repo = GRDBProjectRepository(database: db, clock: .fixed(now))
    }

    private func bundle(newCustomer: Bool = false) throws -> NewProjectBundle {
        var d = ProjectDraft()
        d.jobType = .basementRenovation
        d.customer = newCustomer ? .new(NewCustomerInput(name: "Bob", phone: "647", email: nil, preferredContact: .phone, companyName: nil, secondaryContact: nil, notes: nil)) : .existing(customerId)
        d.address = Address(line: "123 Main St", unit: nil, city: "Toronto", region: "ON", postalCode: nil)
        d.scopeFields = [DraftScopeField(id: UUID(), key: "squareFootage", value: "1200", sortOrder: 0)]
        d.contractValue = Money(38_000, .cad)
        d.labourQuick = LabourQuickInput(workers: 3, dailyRate: Money(250, .cad), days: 10)
        d.materialLines = [DraftEstimateLine(id: UUID(), label: "Lumber", amount: Money(2500, .cad), quantity: nil, unitRate: nil, costGroup: .material, otherKind: nil, sortOrder: 0)]
        d.deposit = DraftDeposit(mode: .percentage(try Percentage.input(20)), deadline: CalendarDate(storage: "2026-10-10"), requiredToStart: true)
        d.schedule = PaymentScheduleTemplate.fourStage.rows(depositPercentage: try Percentage.input(20))
        return try ProjectDraftAssembler.assemble(d, companyId: companyId, currency: .cad, now: now)
    }

    func testCreatePersistsEverythingInOneTransaction() async throws {
        let b = try bundle()
        try await repo.create(b, actor: actor)
        var it = repo.observeDetail(id: b.project.id).makeAsyncIterator()
        let snap = try await it.next() ?? nil
        XCTAssertEqual(snap?.project, b.project)
        XCTAssertEqual(snap?.customer.id, customerId)
        XCTAssertEqual(snap?.estimateLines.count, 2)
        XCTAssertEqual(snap?.scheduleItems.map { $0.amount.storageString }, ["7600.00", "11400.00", "11400.00", "7600.00"])
        let actions = try await db.writer.read { try String.fetchAll($0, sql: "SELECT action FROM activity_log WHERE project_id = ?", arguments: [b.project.id.dbKey]) }
        XCTAssertEqual(actions, ["projectCreated"])
        let details = try await db.writer.read { try String.fetchOne($0, sql: "SELECT details_json FROM activity_log WHERE action = 'projectCreated'") }
        XCTAssertEqual(details, #"{"contractValue":"38000.00","estimateLines":"2","name":"Basement Renovation","scheduleItems":"4"}"#)
    }

    func testCreateWithNewCustomerLogsCustomerCreated() async throws {
        let b = try bundle(newCustomer: true)
        try await repo.create(b, actor: actor)
        let customers = try await GRDBCustomerRepository(database: db, clock: .fixed(now)).list(companyId: companyId)
        XCTAssertEqual(customers.map(\.name), ["Ann", "Bob"])
        let actions = try await db.writer.read { try String.fetchAll($0, sql: "SELECT action FROM activity_log WHERE company_id = ? ORDER BY rowid", arguments: [self.companyId.dbKey]) }
        XCTAssertEqual(actions, ["customerCreated", "projectCreated"])
    }

    func testCreateRollsBackOnConstraintFailure() async throws {
        var b = try bundle()
        // Two schedule items with the same id violate the primary key inside the transaction.
        let dup = b.scheduleItems[0]
        b = NewProjectBundle(project: b.project, scopeFields: b.scopeFields, estimateLines: b.estimateLines, scheduleItems: b.scheduleItems + [dup], newCustomer: nil, warnings: [])
        do { try await repo.create(b, actor: actor); XCTFail("expected throw") } catch {}
        let count = try await db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM projects") }
        XCTAssertEqual(count, 0)
        let lines = try await db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM project_estimate_lines") }
        XCTAssertEqual(lines, 0)
    }

    func testObserveDetailEmitsNilForMissingAndAfterDelete() async throws {
        var it = repo.observeDetail(id: UUID()).makeAsyncIterator()
        let first = try await it.next()
        XCTAssertEqual(first.map { $0 == nil }, true)
        let b = try bundle(); try await repo.create(b, actor: actor)
        var it2 = repo.observeDetail(id: b.project.id).makeAsyncIterator()
        _ = try await it2.next()
        try await repo.softDelete(id: b.project.id, actor: actor)
        let afterDelete = try await it2.next()
        XCTAssertEqual(afterDelete.map { $0 == nil }, true)
    }

    func testObserveDetailEmitsAfterEstimateReplace() async throws {
        let b = try bundle(); try await repo.create(b, actor: actor)
        var it = repo.observeDetail(id: b.project.id).makeAsyncIterator()
        _ = try await it.next()
        let est = GRDBProjectEstimateRepository(database: db, clock: .fixed(now))
        let newLine = ProjectEstimateLine(id: UUID(), companyId: companyId, projectId: b.project.id, costGroup: .material, label: "Paint", amount: Money(800, .cad), quantity: nil, unitRate: nil, sortOrder: 1, createdAt: now, updatedAt: now, deletedAt: nil)
        let existing = b.estimateLines.filter { $0.costGroup == .material }
        try await est.replace(projectId: b.project.id, group: .material, change: EstimateLineChange(upserts: existing + [newLine], deletedIds: [], totalBefore: Money(2500, .cad), totalAfter: Money(3300, .cad)), actor: actor)
        let snap = try await it.next() ?? nil
        XCTAssertEqual(snap?.estimateLines.filter { $0.costGroup == .material }.count, 2)
    }

    func testSaveGuards() async throws {
        let b = try bundle(); try await repo.create(b, actor: actor)
        var usd = b.project; usd.contractValue = Money(1, .usd)
        do { try await repo.save(usd, actor: actor); XCTFail("expected throw") } catch { XCTAssertEqual(error as? DomainError, .currencyMismatch) }
        try await repo.softDelete(id: b.project.id, actor: actor)
        do { try await repo.save(b.project, actor: actor); XCTFail("expected throw") } catch { XCTAssertEqual(error as? DataError, .notFound) }
    }
}
