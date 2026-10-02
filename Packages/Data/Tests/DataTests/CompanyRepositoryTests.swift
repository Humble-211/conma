import XCTest
import GRDB
import Domain
@testable import Data

final class CompanyRepositoryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    func makeCompany(_ id: UUID = UUID()) -> Company { Company(id: id, name: "Northwind Contracting", currencyCode: .cad, createdAt: now, updatedAt: now, deletedAt: nil) }
    func makeOwner(_ companyId: UUID) -> User { User(id: UUID(), companyId: companyId, displayName: "Duc", email: nil, role: .owner, authUserId: nil, createdAt: now, updatedAt: now, deletedAt: nil) }

    func testCurrentIsNilBeforeSetup() async throws {
        let repo = GRDBCompanyRepository(database: try AppDatabase.inMemory(), clock: .fixed(now))
        let current = try await repo.current()
        XCTAssertNil(current)
    }

    func testCreateThenCurrentRoundTrips() async throws {
        let repo = GRDBCompanyRepository(database: try AppDatabase.inMemory(), clock: .fixed(now))
        let company = makeCompany(), owner = makeOwner(company.id)
        try await repo.create(company: company, owner: owner)
        let current = try await repo.current()
        XCTAssertEqual(current?.company, company)
        XCTAssertEqual(current?.owner, owner)
    }

    func testCurrentIsNilWhenCompanyExistsWithoutOwner() async throws {
        let db = try AppDatabase.inMemory()
        try db.writer.write { db in
            try db.execute(sql: "INSERT INTO companies (id, name, currency_code, created_at, updated_at) VALUES (?, 'X', 'CAD', ?, ?)", arguments: [UUID().uuidString.lowercased(), "2026-01-01T00:00:00.000Z", "2026-01-01T00:00:00.000Z"])
        }
        let repo = GRDBCompanyRepository(database: db, clock: .fixed(now))
        let current = try await repo.current()
        XCTAssertNil(current)
    }

    func testCreateRejectsBlankName() async throws {
        let repo = GRDBCompanyRepository(database: try AppDatabase.inMemory(), clock: .fixed(now))
        var company = makeCompany(); company.name = " "
        do { try await repo.create(company: company, owner: makeOwner(company.id)); XCTFail("expected throw") }
        catch { XCTAssertEqual(error as? DomainError, .emptyName) }
    }

    func testUpdateChangesNameAndTimestamp() async throws {
        let later = now.addingTimeInterval(60)
        let repo = GRDBCompanyRepository(database: try AppDatabase.inMemory(), clock: .fixed(later))
        var company = makeCompany(); try await repo.create(company: company, owner: makeOwner(company.id))
        company.name = "Northwind Builders"
        try await repo.update(company: company)
        let current = try await repo.current()
        XCTAssertEqual(current?.company.name, "Northwind Builders")
        XCTAssertEqual(current?.company.updatedAt, later)
    }
}
