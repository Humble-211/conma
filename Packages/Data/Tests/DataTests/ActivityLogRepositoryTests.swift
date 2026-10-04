import XCTest
import GRDB
import Domain
@testable import Data

final class ActivityLogRepositoryTests: XCTestCase {
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

    func testObserveForProjectLimitAndOrder() async throws {
        let p = project(status: .scheduled)
        try await repo.save(p, actor: actor)
        try await repo.changeStatus(id: p.id, to: .inProgress, actor: actor)
        try await repo.setManualProgress(id: p.id, to: 10, actor: actor)
        let logs = GRDBActivityLogRepository(database: db)
        var it = logs.observeForProject(projectId: p.id, limit: 2).makeAsyncIterator()
        let first = try await it.next()!
        XCTAssertEqual(first.map(\.action), [.progressChanged, .statusChanged])
        try await repo.changeStatus(id: p.id, to: .onHold, actor: actor)
        let second = try await it.next()!
        XCTAssertEqual(second.first?.action, .statusChanged)
        XCTAssertEqual(second.count, 2)
        let all = try await logs.list(projectId: p.id)
        XCTAssertEqual(all.count, 4)
    }

    func testUnknownActionRowIsSkipped() async throws {
        let p = project(status: .scheduled)
        try await repo.save(p, actor: actor)                                                // projectCreated
        let stamp = "2026-10-03T12:00:00.000Z"
        try await db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO activity_log (id, company_id, created_at, updated_at, deleted_at, sync_state, user_id, actor_name, action, entity_type, entity_id, project_id, details_json, occurred_at)
                VALUES (?, ?, ?, ?, NULL, 'pending', NULL, 'Duc', 'futureAction', 'project', ?, ?, '{}', ?)
                """, arguments: [UUID().uuidString.lowercased(), self.companyId.uuidString.lowercased(), stamp, stamp, p.id.uuidString.lowercased(), p.id.uuidString.lowercased(), stamp])
        }
        let logs = GRDBActivityLogRepository(database: db)
        var it = logs.observeForProject(projectId: p.id, limit: 5).makeAsyncIterator()
        await XCTAssertEqualAsync(try await it.next()!.map(\.action), [.projectCreated])
        await XCTAssertEqualAsync(try await logs.list(projectId: p.id).map(\.action), [.projectCreated])
    }
}
