import XCTest
import GRDB
import Domain
@testable import Data

final class ProjectMutationTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    var db: AppDatabase!
    var companyId: UUID!
    var customer: Customer!
    var actor: ActivityActor!
    var repo: GRDBProjectRepository!

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        let company = Company(id: UUID(), name: "N", currencyCode: .cad, createdAt: now, updatedAt: now, deletedAt: nil)
        let owner = User(id: UUID(), companyId: company.id, displayName: "Duc", email: nil, role: .owner, authUserId: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBCompanyRepository(database: db, clock: .fixed(now)).create(company: company, owner: owner)
        companyId = company.id
        actor = ActivityActor(userId: owner.id, name: "Duc")
        customer = Customer(id: UUID(), companyId: companyId, name: "Ann Lee", phone: nil, email: nil, preferredContact: nil, companyName: nil, secondaryContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBCustomerRepository(database: db, clock: .fixed(now)).save(customer)
        repo = GRDBProjectRepository(database: db, clock: .fixed(now))
    }

    func project(status: ProjectStatus = .inProgress) -> Project {
        Project(id: UUID(), companyId: companyId, customerId: customer.id, name: "P", jobType: .kitchen, customJobType: nil, status: status,
                address: Address(line: "1", unit: nil, city: nil, region: nil, postalCode: nil), scopeDescription: nil, scopeFields: [],
                startDate: nil, estimatedCompletionDate: nil, workingDays: nil, hoursPerDay: nil, workersPerDay: nil,
                contractValue: Money(1000, .cad), manualProgress: nil, depositRequiredToStart: false, createdAt: now, updatedAt: now, deletedAt: nil)
    }

    func activities(_ pid: UUID) async throws -> [(String, String)] {
        try await db.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT action, details_json FROM activity_log WHERE project_id = ? ORDER BY created_at, rowid", arguments: [pid.dbKey]).map { ($0["action"], $0["details_json"]) }
        }
    }

    func testChangeStatusWritesActivity() async throws {
        let p = project(status: .scheduled)
        try await repo.save(p, actor: actor)
        try await repo.changeStatus(id: p.id, to: .inProgress, actor: actor)
        let status = try await repo.get(id: p.id)?.status
        XCTAssertEqual(status, .inProgress)
        let a = try await activities(p.id)
        XCTAssertEqual(a.last?.0, "statusChanged")
        XCTAssertEqual(a.last?.1, #"{"from":"scheduled","to":"inProgress"}"#)
    }

    func testChangeStatusSameStatusWritesNoActivity() async throws {
        let p = project(status: .scheduled)
        try await repo.save(p, actor: actor)
        let before = try await activities(p.id).count
        try await repo.changeStatus(id: p.id, to: .scheduled, actor: actor)
        let after = try await activities(p.id).count
        XCTAssertEqual(after, before)
    }

    func testChangeStatusMissingProjectThrowsNotFound() async {
        await XCTAssertThrowsErrorAsync(try await repo.changeStatus(id: UUID(), to: .closed, actor: actor)) { XCTAssertEqual($0 as? DomainError, .notFound) }
    }

    func testSoftDeleteMissingProjectThrowsDomainNotFound() async {
        await XCTAssertThrowsErrorAsync(try await repo.softDelete(id: UUID(), actor: actor)) { XCTAssertEqual($0 as? DomainError, .notFound) }
    }

    func testSetProgressWritesFromEmptyForNil() async throws {
        let p = project()
        try await repo.save(p, actor: actor)
        try await repo.setManualProgress(id: p.id, to: 60, actor: actor)
        let first = try await activities(p.id).last?.1
        XCTAssertEqual(first, #"{"from":"","to":"60"}"#)
        try await repo.setManualProgress(id: p.id, to: nil, actor: actor)
        let second = try await activities(p.id).last?.1
        XCTAssertEqual(second, #"{"from":"60","to":""}"#)
        let progress = try await repo.get(id: p.id)?.manualProgress
        XCTAssertNil(progress)
    }

    func testSetProgressSameValueWritesNoActivity() async throws {
        let p = project()
        try await repo.save(p, actor: actor)
        let before = try await activities(p.id).count
        try await repo.setManualProgress(id: p.id, to: nil, actor: actor)
        let after = try await activities(p.id).count
        XCTAssertEqual(after, before)
    }

    func testSetProgressOutOfRangeThrows() async throws {
        let p = project()
        try await repo.save(p, actor: actor)
        await XCTAssertThrowsErrorAsync(try await repo.setManualProgress(id: p.id, to: 101, actor: actor)) { XCTAssertEqual($0 as? DomainError, .invalidProgress) }
    }

    func testChangeCustomerWritesNamesAndRejectsBadTargets() async throws {
        let p = project()
        try await repo.save(p, actor: actor)
        let bob = Customer(id: UUID(), companyId: companyId, name: "Bob", phone: nil, email: nil, preferredContact: nil, companyName: nil, secondaryContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBCustomerRepository(database: db, clock: .fixed(now)).save(bob)
        try await repo.changeCustomer(id: p.id, to: bob.id, actor: actor)
        let current = try await repo.get(id: p.id)?.customerId
        XCTAssertEqual(current, bob.id)
        let last = try await activities(p.id).last
        XCTAssertEqual(last?.0, "customerChanged")
        XCTAssertEqual(last?.1, #"{"from":"Ann Lee","fromId":"\#(customer.id.dbKey)","to":"Bob","toId":"\#(bob.id.dbKey)"}"#)
        await XCTAssertThrowsErrorAsync(try await repo.changeCustomer(id: p.id, to: UUID(), actor: actor)) { XCTAssertEqual($0 as? DomainError, .notFound) }
        let deletedAt = Timestamps.string(now)
        try await db.writer.write { db in try db.execute(sql: "UPDATE customers SET deleted_at = ? WHERE id = ?", arguments: [deletedAt, bob.id.dbKey]) }
        await XCTAssertThrowsErrorAsync(try await repo.changeCustomer(id: p.id, to: bob.id, actor: actor)) { XCTAssertEqual($0 as? DomainError, .customerDeleted) }
    }

    func testChangeCustomerRejectsOtherCompany() async throws {
        let p = project()
        try await repo.save(p, actor: actor)
        let other = Company(id: UUID(), name: "O", currencyCode: .cad, createdAt: now, updatedAt: now, deletedAt: nil)
        let owner2 = User(id: UUID(), companyId: other.id, displayName: "O", email: nil, role: .owner, authUserId: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBCompanyRepository(database: db, clock: .fixed(now)).create(company: other, owner: owner2)
        let foreign = Customer(id: UUID(), companyId: other.id, name: "F", phone: nil, email: nil, preferredContact: nil, companyName: nil, secondaryContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBCustomerRepository(database: db, clock: .fixed(now)).save(foreign)
        await XCTAssertThrowsErrorAsync(try await repo.changeCustomer(id: p.id, to: foreign.id, actor: actor)) { XCTAssertEqual($0 as? DomainError, .crossCompany) }
    }
}
