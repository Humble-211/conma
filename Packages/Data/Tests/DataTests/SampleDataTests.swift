import XCTest
import Domain
@testable import Data

final class SampleDataTests: XCTestCase {
    func testSeedCreatesThreeProjectsAndIsIdempotent() async throws {
        let db = try AppDatabase.inMemory()
        let clock = Clock.fixed(Date(timeIntervalSince1970: 1_790_000_000))
        let setup = try await SampleData.seedIfEmpty(db, clock: clock)
        XCTAssertEqual(setup.company.name, "Northwind Contracting")
        XCTAssertEqual(setup.owner.displayName, "Duc")
        let projects = try await GRDBProjectRepository(database: db, clock: clock).list(companyId: setup.company.id)
        XCTAssertEqual(Set(projects.map(\.status)), [.inProgress, .awaitingDeposit, .completed])
        XCTAssertEqual(projects.first { $0.status == .inProgress }?.manualProgress, 65)
        XCTAssertEqual(projects.first { $0.status == .inProgress }?.contractValue.storageString, "38000.00")

        let again = try await SampleData.seedIfEmpty(db, clock: clock)
        XCTAssertEqual(again.company.id, setup.company.id)
        let count = try await GRDBProjectRepository(database: db, clock: clock).list(companyId: setup.company.id).count
        XCTAssertEqual(count, 3)
    }
}
