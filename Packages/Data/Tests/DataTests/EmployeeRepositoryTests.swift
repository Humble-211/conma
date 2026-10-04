// Packages/Data/Tests/DataTests/EmployeeRepositoryTests.swift
import XCTest
import GRDB
import Domain
@testable import Data

final class EmployeeRepositoryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    var db: AppDatabase!
    var f: Fixture!
    var repo: GRDBEmployeeRepository!

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        f = try await makeFixture(db, now: now)
        repo = GRDBEmployeeRepository(database: db, clock: .fixed(now))
    }

    func person(_ name: String, daily: Int? = 250, currency: CurrencyCode = .cad) -> Employee {
        Employee(id: UUID(), companyId: f.companyId, name: name, phone: nil, role: nil, trade: "Carpenter", hourlyRate: nil,
                 dailyRate: daily.map { Money(Decimal($0), currency) }, certifications: nil, emergencyContact: nil, notes: nil,
                 createdAt: now, updatedAt: now, deletedAt: nil)
    }
    func firstEmission() async throws -> [Employee] {
        var it = repo.observeAll(companyId: f.companyId).makeAsyncIterator()
        return try await XCTUnwrapAsync(try await it.next())
    }

    func testCreateAndObserveLiveByName() async throws {
        try await repo.create(person("mike"))
        try await repo.create(person("David"))
        await XCTAssertEqualAsync(try await self.firstEmission().map(\.name), ["David", "mike"])
    }

    func testValidation() async throws {
        await XCTAssertThrowsErrorAsync(try await self.repo.create(self.person("  "))) { XCTAssertEqual($0 as? DomainError, .emptyName) }
        await XCTAssertThrowsErrorAsync(try await self.repo.create(self.person("Neg", daily: -1))) { XCTAssertEqual($0 as? DomainError, .negativeAmount) }
        await XCTAssertThrowsErrorAsync(try await self.repo.create(self.person("Usd", currency: .usd))) { XCTAssertEqual($0 as? DomainError, .currencyMismatch) }
    }

    func testUpdateNoOpAndChange() async throws {
        let mike = person("Mike")
        try await repo.create(mike)
        let later = GRDBEmployeeRepository(database: db, clock: .fixed(now.addingTimeInterval(60)))
        try await later.update(mike)
        await XCTAssertEqualAsync(try await self.repo.get(id: mike.id, includingDeleted: false)?.updatedAt, now)
        var raised = mike
        raised.dailyRate = Money(275, .cad)
        try await later.update(raised)
        let back = try await XCTUnwrapAsync(try await repo.get(id: mike.id, includingDeleted: false))
        XCTAssertEqual(back.dailyRate, Money(275, .cad))
        XCTAssertEqual(back.updatedAt, now.addingTimeInterval(60))
        XCTAssertEqual(back.createdAt, now)
    }

    func testSoftDeleteHidesButKeepsHistoryLookup() async throws {
        let mike = person("Mike"), john = person("John")
        try await repo.create(mike)
        try await repo.create(john)
        try await repo.softDelete(id: mike.id)
        await XCTAssertEqualAsync(try await self.firstEmission().map(\.name), ["John"])
        await XCTAssertNilAsync(try await self.repo.get(id: mike.id, includingDeleted: false))
        let gone = try await XCTUnwrapAsync(try await repo.get(id: mike.id, includingDeleted: true))
        XCTAssertNotNil(gone.deletedAt)
        await XCTAssertThrowsErrorAsync(try await self.repo.update(mike)) { XCTAssertEqual($0 as? DomainError, .notFound) }
        await XCTAssertThrowsErrorAsync(try await self.repo.softDelete(id: mike.id)) { XCTAssertEqual($0 as? DomainError, .notFound) }
    }
}
