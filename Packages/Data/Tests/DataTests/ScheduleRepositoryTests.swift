import XCTest
import GRDB
import Domain
@testable import Data

final class ScheduleRepositoryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    var db: AppDatabase!; var companyId: UUID!; var projectId: UUID!; var actor: ActivityActor!

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        let setup = try await SampleData.seedIfEmpty(db, clock: .fixed(now))
        companyId = setup.company.id
        actor = ActivityActor(userId: setup.owner.id, name: "Duc")
        projectId = try await GRDBProjectRepository(database: db, clock: .fixed(now)).list(companyId: companyId).first { $0.status == .completed }!.id  // Roof: no schedule in seed
    }

    private func item(_ label: String, _ amount: Decimal, deposit: Bool = false, order: Int = 0, id: UUID = UUID()) -> PaymentScheduleItem {
        PaymentScheduleItem(id: id, companyId: companyId, projectId: projectId, label: label, amount: Money(amount, .cad), percentage: nil, dueDate: nil, triggerText: nil, isDeposit: deposit, notes: nil, sortOrder: order, createdAt: now, updatedAt: now, deletedAt: nil)
    }

    func testReplaceRoundTripAndActivity() async throws {
        let repo = GRDBPaymentScheduleRepository(database: db, clock: .fixed(now))
        let dep = item("schedule.row.deposit", 5000, deposit: true), fin = item("schedule.row.final", 13_500, order: 1)
        try await repo.replace(projectId: projectId, change: ScheduleItemChange(upserts: [dep, fin], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(18_500, .cad)), actor: actor)
        let stored = try await repo.items(projectId: projectId)
        XCTAssertEqual(stored, [dep, fin])
        let details = try await db.writer.read { try String.fetchOne($0, sql: "SELECT details_json FROM activity_log WHERE action = 'scheduleChanged' AND project_id = ?", arguments: [self.projectId.dbKey]) }
        XCTAssertEqual(details, #"{"from":"0.00","to":"18500.00"}"#)
    }

    func testDeletingItemNullifiesPayments() async throws {
        let repo = GRDBPaymentScheduleRepository(database: db, clock: .fixed(now))
        let dep = item("schedule.row.deposit", 5000, deposit: true)
        try await repo.replace(projectId: projectId, change: ScheduleItemChange(upserts: [dep], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(5000, .cad)), actor: actor)
        let (c, p, i) = (companyId.dbKey, projectId.dbKey, dep.id.dbKey)
        try await db.writer.write { db in
            try db.execute(sql: "INSERT INTO payments (id, company_id, project_id, schedule_item_id, amount, paid_on, method, created_at, updated_at) VALUES ('pay1', ?, ?, ?, '5000.00', '2026-10-05', 'cash', ?, ?)",
                           arguments: [c, p, i, "2026-10-05T00:00:00.000Z", "2026-10-05T00:00:00.000Z"])
        }
        try await repo.replace(projectId: projectId, change: ScheduleItemChange(upserts: [], deletedIds: [dep.id], totalBefore: Money(5000, .cad), totalAfter: .zero(.cad)), actor: actor)
        let link: Row? = try await db.writer.read { db -> Row? in try Row.fetchOne(db, sql: "SELECT schedule_item_id, deleted_at FROM payments WHERE id = 'pay1'") }
        XCTAssertNil(link?["schedule_item_id"] as String?)
        XCTAssertNil(link?["deleted_at"] as String?, "payment itself stays live")
        let remaining = try await repo.items(projectId: projectId)
        XCTAssertEqual(remaining, [])
    }

    func testScopeMismatchRejected() async throws {
        let repo = GRDBPaymentScheduleRepository(database: db, clock: .fixed(now))
        let foreign = PaymentScheduleItem(id: UUID(), companyId: companyId, projectId: UUID(), label: "x", amount: Money(1, .cad), percentage: nil, dueDate: nil, triggerText: nil, isDeposit: false, notes: nil, sortOrder: 0, createdAt: now, updatedAt: now, deletedAt: nil)
        do {
            try await repo.replace(projectId: projectId, change: ScheduleItemChange(upserts: [foreign], deletedIds: [], totalBefore: .zero(.cad), totalAfter: Money(1, .cad)), actor: actor)
            XCTFail("expected throw")
        } catch { XCTAssertEqual(error as? DataError, .scopeMismatch) }
    }
}
