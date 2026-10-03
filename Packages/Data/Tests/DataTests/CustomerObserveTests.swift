import XCTest
import Domain
@testable import Data

final class CustomerObserveTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testObserveAllEmitsSortedAndUpdates() async throws {
        let db = try AppDatabase.inMemory()
        let setup = try await SampleData.seedIfEmpty(db, clock: .fixed(now))
        let repo = GRDBCustomerRepository(database: db, clock: .fixed(now))
        var it = repo.observeAll(companyId: setup.company.id).makeAsyncIterator()
        let first = try await it.next()
        XCTAssertEqual(first?.map(\.name), ["Ann Lee", "David Nguyen", "Maria Santos"])
        try await repo.save(Customer(id: UUID(), companyId: setup.company.id, name: "Bob", phone: nil, email: nil, preferredContact: nil, companyName: nil, secondaryContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil))
        let second = try await it.next()
        XCTAssertEqual(second?.map(\.name), ["Ann Lee", "Bob", "David Nguyen", "Maria Santos"])
    }

    func testProjectsForCustomer() async throws {
        let db = try AppDatabase.inMemory()
        let setup = try await SampleData.seedIfEmpty(db, clock: .fixed(now))
        let repo = GRDBCustomerRepository(database: db, clock: .fixed(now))
        let ann = try await repo.list(companyId: setup.company.id).first { $0.name == "Ann Lee" }!
        let projects = try await repo.projects(customerId: ann.id)
        XCTAssertEqual(projects.map(\.name), ["Basement Renovation"])
        XCTAssertEqual(try await repo.projects(customerId: UUID()), [])
    }
}
