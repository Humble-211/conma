import XCTest
import GRDB
import Domain
@testable import Data

final class CustomerRepositoryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    var db: AppDatabase!
    var companyId: UUID!
    var actor: ActivityActor!

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        let company = Company(id: UUID(), name: "N", currencyCode: .cad, createdAt: now, updatedAt: now, deletedAt: nil)
        let owner = User(id: UUID(), companyId: company.id, displayName: "Duc", email: nil, role: .owner, authUserId: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBCompanyRepository(database: db, clock: .fixed(now)).create(company: company, owner: owner)
        companyId = company.id
        actor = ActivityActor(userId: owner.id, name: owner.displayName)
    }

    func customer(_ name: String) -> Customer {
        Customer(id: UUID(), companyId: companyId, name: name, phone: "416", email: nil, preferredContact: .text, companyName: nil, secondaryContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
    }

    func testSaveListGetRoundTrip() async throws {
        let repo = GRDBCustomerRepository(database: db, clock: .fixed(now))
        let ann = customer("Ann"), bob = customer("Bob")
        try await repo.save(bob); try await repo.save(ann)
        let listed = try await repo.list(companyId: companyId)
        XCTAssertEqual(listed.map(\.name), ["Ann", "Bob"])
        let fetched = try await repo.get(id: ann.id)
        XCTAssertEqual(fetched, ann)
    }

    func testSoftDeleteHidesFromListAndKeepsRow() async throws {
        let repo = GRDBCustomerRepository(database: db, clock: .fixed(now))
        let ann = customer("Ann"); try await repo.save(ann)
        try await repo.softDelete(id: ann.id, actor: actor)
        let listed = try await repo.list(companyId: companyId)
        XCTAssertEqual(listed, [])
        let deletedAt = try db.writer.read { try String.fetchOne($0, sql: "SELECT deleted_at FROM customers WHERE id = ?", arguments: [ann.id.uuidString.lowercased()]) }
        XCTAssertNotNil(deletedAt)
        let fetched = try await repo.get(id: ann.id)
        XCTAssertNil(fetched)
    }

    func testSoftDeleteRejectedWhenLiveProjectExists() async throws {
        let repo = GRDBCustomerRepository(database: db, clock: .fixed(now))
        let ann = customer("Ann"); try await repo.save(ann)
        try db.writer.write { db in
            try db.execute(sql: """
                INSERT INTO projects (id, company_id, customer_id, name, job_type, status, address_line, contract_value, deposit_required_to_start, created_at, updated_at)
                VALUES (?, ?, ?, 'P', 'kitchen', 'inProgress', '1 Main', '0.00', 0, ?, ?)
                """, arguments: [UUID().uuidString.lowercased(), self.companyId.uuidString.lowercased(), ann.id.uuidString.lowercased(), "2026-01-01T00:00:00.000Z", "2026-01-01T00:00:00.000Z"])
        }
        do { try await repo.softDelete(id: ann.id, actor: actor); XCTFail("expected throw") }
        catch { XCTAssertEqual(error as? DomainError, .customerHasProjects) }
    }

    func testSaveRejectsBlankName() async throws {
        let repo = GRDBCustomerRepository(database: db, clock: .fixed(now))
        do { try await repo.save(customer("")); XCTFail("expected throw") }
        catch { XCTAssertEqual(error as? DomainError, .emptyName) }
    }
}
