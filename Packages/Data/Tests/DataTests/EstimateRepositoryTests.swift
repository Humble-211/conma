import XCTest
import GRDB
import Domain
@testable import Data

final class EstimateRepositoryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    var db: AppDatabase!; var companyId: UUID!; var projectId: UUID!; var actor: ActivityActor!

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        let setup = try await SampleData.seedIfEmpty(db, clock: .fixed(now), today: CalendarDate(now, timeZone: .gmt))
        companyId = setup.company.id
        actor = ActivityActor(userId: setup.owner.id, name: "Duc")
        let projects = try await GRDBProjectRepository(database: db, clock: .fixed(now)).list(companyId: companyId)
        projectId = projects.first { $0.status == .awaitingDeposit }!.id   // Kitchen: no estimate lines in seed
    }

    private func line(_ label: String, _ amount: Decimal, group: CostGroup = .material, id: UUID = UUID(), order: Int = 0, created: Date? = nil) -> ProjectEstimateLine {
        ProjectEstimateLine(id: id, companyId: companyId, projectId: projectId, costGroup: group, label: label, amount: Money(amount, .cad), quantity: nil, unitRate: nil, sortOrder: order, createdAt: created ?? now, updatedAt: now, deletedAt: nil)
    }
    private func actions() throws -> [String] { try db.writer.read { try String.fetchAll($0, sql: "SELECT action FROM activity_log WHERE project_id = ? ORDER BY rowid", arguments: [self.projectId.dbKey]) } }

    func testReplaceInsertsAndReadsBack() async throws {
        let repo = GRDBProjectEstimateRepository(database: db, clock: .fixed(now))
        let a = line("Lumber", 2500), b = line("Drywall", 1600, order: 1)
        try await repo.replace(projectId: projectId, group: .material, change: EstimateLineChange(upserts: [a, b], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(4100, .cad)), actor: actor)
        let lines = try await repo.lines(projectId: projectId)
        XCTAssertEqual(lines, [a, b])
        XCTAssertEqual(try actions(), ["projectCreated", "scheduleChanged", "estimateChanged"])  // seed gives Kitchen one deposit schedule item
        let details = try await db.writer.read { try String.fetchOne($0, sql: "SELECT details_json FROM activity_log WHERE action = 'estimateChanged' AND project_id = ?", arguments: [self.projectId.dbKey]) }
        XCTAssertEqual(details, #"{"from":"0.00","group":"material","to":"4100.00"}"#)
    }

    func testReplaceSoftDeletesAndKeepsCreatedAt() async throws {
        let repo = GRDBProjectEstimateRepository(database: db, clock: .fixed(now))
        let a = line("Lumber", 2500), b = line("Drywall", 1600, order: 1)
        try await repo.replace(projectId: projectId, group: .material, change: EstimateLineChange(upserts: [a, b], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(4100, .cad)), actor: actor)
        let later = now.addingTimeInterval(600)
        let repo2 = GRDBProjectEstimateRepository(database: db, clock: .fixed(later))
        var b2 = b; b2.amount = Money(1800, .cad); b2.updatedAt = later
        try await repo2.replace(projectId: projectId, group: .material, change: EstimateLineChange(upserts: [b2], deletedIds: [a.id], totalBefore: Money(4100, .cad), totalAfter: Money(1800, .cad)), actor: actor)
        let lines = try await repo2.lines(projectId: projectId)
        XCTAssertEqual(lines.map(\.id), [b.id])
        XCTAssertEqual(lines[0].createdAt, now)
        XCTAssertEqual(lines[0].amount.storageString, "1800.00")
        let deletedAt = try await db.writer.read { try String.fetchOne($0, sql: "SELECT deleted_at FROM project_estimate_lines WHERE id = ?", arguments: [a.id.dbKey]) }
        XCTAssertNotNil(deletedAt)
    }

    func testNoActivityWhenTotalUnchanged() async throws {
        let repo = GRDBProjectEstimateRepository(database: db, clock: .fixed(now))
        let a = line("Lumber", 2500)
        try await repo.replace(projectId: projectId, group: .material, change: EstimateLineChange(upserts: [a], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(2500, .cad)), actor: actor)
        var renamed = a; renamed.label = "Lumber (SPF)"
        try await repo.replace(projectId: projectId, group: .material, change: EstimateLineChange(upserts: [renamed], deletedIds: [], totalBefore: Money(2500, .cad), totalAfter: Money(2500, .cad)), actor: actor)
        XCTAssertEqual(try actions().filter { $0 == "estimateChanged" }.count, 1)
    }

    func testScopeMismatchRejected() async throws {
        let repo = GRDBProjectEstimateRepository(database: db, clock: .fixed(now))
        let wrongGroup = line("Mike", 2000, group: .labour)
        do {
            try await repo.replace(projectId: projectId, group: .material, change: EstimateLineChange(upserts: [wrongGroup], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(2000, .cad)), actor: actor)
            XCTFail("expected throw")
        } catch { XCTAssertEqual(error as? DataError, .scopeMismatch) }
        var otherProject = line("Lumber", 1)
        otherProject = ProjectEstimateLine(id: otherProject.id, companyId: companyId, projectId: UUID(), costGroup: .material, label: "x", amount: Money(1, .cad), quantity: nil, unitRate: nil, sortOrder: 0, createdAt: now, updatedAt: now, deletedAt: nil)
        do {
            try await repo.replace(projectId: projectId, group: .material, change: EstimateLineChange(upserts: [otherProject], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(1, .cad)), actor: actor)
            XCTFail("expected throw")
        } catch { XCTAssertEqual(error as? DataError, .scopeMismatch) }
    }
}
