import XCTest
import GRDB
import Domain
@testable import Data

final class ProjectRepositoryTests: XCTestCase {
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

    func project(_ name: String = "123 Main St", status: ProjectStatus = .inProgress) -> Project {
        let id = UUID()
        return Project(id: id, companyId: companyId, customerId: customer.id, name: name, jobType: .basementRenovation, customJobType: nil, status: status,
                       address: Address(line: "123 Main St", unit: "2", city: "Toronto", region: "ON", postalCode: "M1M 1M1"), scopeDescription: "1200 sqft",
                       scopeFields: [ProjectScopeField(id: UUID(), companyId: companyId, projectId: id, fieldKey: "squareFootage", valueText: "1200", sortOrder: 0, createdAt: now, updatedAt: now, deletedAt: nil)],
                       startDate: CalendarDate(storage: "2026-10-01"), estimatedCompletionDate: CalendarDate(storage: "2026-10-20"), workingDays: 10,
                       hoursPerDay: Decimal(string: "8.5"), workersPerDay: 3, contractValue: Money(38_000, .cad), manualProgress: 65, depositRequiredToStart: true,
                       createdAt: now, updatedAt: now, deletedAt: nil)
    }

    private func activityActions(_ projectId: UUID) async throws -> [String] {
        let key = projectId.dbKey
        return try await db.writer.read { try String.fetchAll($0, sql: "SELECT action FROM activity_log WHERE project_id = ? ORDER BY created_at, rowid", arguments: [key]) }
    }

    func testSaveAndGetRoundTripIncludingScopeFields() async throws {
        let p = project()
        try await repo.save(p, actor: actor)
        let fetched = try await repo.get(id: p.id)
        XCTAssertEqual(fetched, p)
        let actions = try await activityActions(p.id)
        XCTAssertEqual(actions, ["projectCreated"])
    }

    func testUpdateLogsContractStatusAndProgressChanges() async throws {
        var p = project(); try await repo.save(p, actor: actor)
        p.contractValue = Money(45_000, .cad); p.status = .onHold; p.manualProgress = 70; p.name = "Renamed"
        try await repo.save(p, actor: actor)
        let actions = try await activityActions(p.id)
        XCTAssertEqual(actions, ["projectCreated", "contractValueChanged", "statusChanged", "progressChanged"])
        let details = try await db.writer.read { try String.fetchOne($0, sql: "SELECT details_json FROM activity_log WHERE action = 'contractValueChanged'") }
        XCTAssertEqual(details, #"{"from":"38000.00","to":"45000.00"}"#)
        // Renaming alone adds no activity row.
        p.name = "Renamed again"; try await repo.save(p, actor: actor)
        let finalActions = try await activityActions(p.id)
        XCTAssertEqual(finalActions.count, 4)
    }

    func testScopeFieldsReplacedWithSoftDelete() async throws {
        var p = project(); try await repo.save(p, actor: actor)
        p.scopeFields = [ProjectScopeField(id: UUID(), companyId: companyId, projectId: p.id, fieldKey: "rooms", valueText: "3", sortOrder: 0, createdAt: now, updatedAt: now, deletedAt: nil)]
        try await repo.save(p, actor: actor)
        let fetched = try await repo.get(id: p.id)
        XCTAssertEqual(fetched?.scopeFields.map(\.fieldKey), ["rooms"])
        let pid = p.id.dbKey
        let rows = try await db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM project_scope_fields WHERE project_id = ?", arguments: [pid]) }
        XCTAssertEqual(rows, 2)
    }

    func testValidationFailureRollsBack() async throws {
        var p = project(); p.estimatedCompletionDate = CalendarDate(storage: "2026-09-01")
        do { try await repo.save(p, actor: actor); XCTFail("expected throw") } catch { XCTAssertEqual(error as? DomainError, .completionBeforeStart) }
        let count = try await db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM projects") }
        XCTAssertEqual(count, 0)
        let actions = try await activityActions(p.id)
        XCTAssertEqual(actions, [])
    }

    func testConstraintFailureInsideTransactionRollsBackEverything() async throws {
        var p = project()
        let duplicate = ProjectScopeField(id: UUID(), companyId: companyId, projectId: p.id, fieldKey: "squareFootage", valueText: "900", sortOrder: 1, createdAt: now, updatedAt: now, deletedAt: nil)
        p.scopeFields.append(duplicate)
        do { try await repo.save(p, actor: actor); XCTFail("expected unique constraint failure") } catch {}
        let count = try await db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM projects") }
        XCTAssertEqual(count, 0)
        let actions = try await activityActions(p.id)
        XCTAssertEqual(actions, [])
    }

    func testListAndSummariesExcludeDeleted() async throws {
        let a = project("A"), b = project("B")
        try await repo.save(a, actor: actor); try await repo.save(b, actor: actor)
        try await repo.softDelete(id: a.id, actor: actor)
        let listed = try await repo.list(companyId: companyId)
        XCTAssertEqual(listed.map(\.name), ["B"])
        var iterator = repo.observeSummaries(companyId: companyId).makeAsyncIterator()
        let first = try await iterator.next()
        XCTAssertEqual(first?.map(\.project.name), ["B"])
        XCTAssertEqual(first?.first?.customerName, "Ann Lee")
    }

    func testObserveEmitsOnChange() async throws {
        var iterator = repo.observeSummaries(companyId: companyId).makeAsyncIterator()
        let initial = try await iterator.next()
        XCTAssertEqual(initial?.count, 0)
        try await repo.save(project("New"), actor: actor)
        let next = try await iterator.next()
        XCTAssertEqual(next?.map(\.project.name), ["New"])
    }

    func testCascadeSoftDeleteCoversChildrenAndNotificationsKeepsActivityLog() async throws {
        let p = project(); try await repo.save(p, actor: actor)
        let ts = "2026-10-05T00:00:00.000Z"
        let taskId = UUID().dbKey, expenseId = UUID().dbKey, employeeId = UUID().dbKey, logId = UUID().dbKey, itemId = UUID().dbKey
        let c = companyId.dbKey, pid = p.id.dbKey
        try await db.writer.write { db in
            try db.execute(sql: "INSERT INTO employees (id, company_id, name, created_at, updated_at) VALUES (?, ?, 'Mike', ?, ?)", arguments: [employeeId, c, ts, ts])
            try db.execute(sql: "INSERT INTO project_tasks (id, company_id, project_id, name, status, sort_order, created_at, updated_at) VALUES (?, ?, ?, 'Framing', 'inProgress', 0, ?, ?)", arguments: [taskId, c, pid, ts, ts])
            try db.execute(sql: "INSERT INTO task_checklist_items (id, company_id, task_id, title, sort_order, created_at, updated_at) VALUES (?, ?, ?, 'Walls', 0, ?, ?)", arguments: [UUID().dbKey, c, taskId, ts, ts])
            try db.execute(sql: "INSERT INTO task_assignees (id, company_id, task_id, employee_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)", arguments: [UUID().dbKey, c, taskId, employeeId, ts, ts])
            try db.execute(sql: "INSERT INTO project_workers (id, company_id, project_id, employee_id, work_date, created_at, updated_at) VALUES (?, ?, ?, ?, '2026-10-05', ?, ?)", arguments: [UUID().dbKey, c, pid, employeeId, ts, ts])
            try db.execute(sql: "INSERT INTO project_estimate_lines (id, company_id, project_id, cost_group, label, amount, sort_order, created_at, updated_at) VALUES (?, ?, ?, 'material', 'Lumber', '2500.00', 0, ?, ?)", arguments: [UUID().dbKey, c, pid, ts, ts])
            try db.execute(sql: "INSERT INTO payment_schedule_items (id, company_id, project_id, label, amount, sort_order, created_at, updated_at) VALUES (?, ?, ?, 'Deposit', '5000.00', 0, ?, ?)", arguments: [itemId, c, pid, ts, ts])
            try db.execute(sql: "INSERT INTO payments (id, company_id, project_id, schedule_item_id, amount, paid_on, method, created_at, updated_at) VALUES (?, ?, ?, ?, '5000.00', '2026-10-05', 'cash', ?, ?)", arguments: [UUID().dbKey, c, pid, itemId, ts, ts])
            try db.execute(sql: "INSERT INTO expenses (id, company_id, project_id, category, cost_group, amount, tax, spent_on, created_at, updated_at) VALUES (?, ?, ?, 'materials', 'material', '100.00', '13.00', '2026-10-05', ?, ?)", arguments: [expenseId, c, pid, ts, ts])
            try db.execute(sql: "INSERT INTO receipt_images (id, company_id, expense_id, file_path, page_index, created_at, updated_at) VALUES (?, ?, ?, 'r.jpg', 0, ?, ?)", arguments: [UUID().dbKey, c, expenseId, ts, ts])
            try db.execute(sql: "INSERT INTO labour_entries (id, company_id, project_id, employee_id, work_date, days, daily_rate, created_at, updated_at) VALUES (?, ?, ?, ?, '2026-10-05', '1', '250.00', ?, ?)", arguments: [UUID().dbKey, c, pid, employeeId, ts, ts])
            try db.execute(sql: "INSERT INTO daily_logs (id, company_id, project_id, log_date, created_at, updated_at) VALUES (?, ?, ?, '2026-10-05', ?, ?)", arguments: [logId, c, pid, ts, ts])
            try db.execute(sql: "INSERT INTO photos (id, company_id, project_id, daily_log_id, category, taken_at, file_path, created_at, updated_at) VALUES (?, ?, ?, ?, 'progress', ?, 'p.jpg', ?, ?)", arguments: [UUID().dbKey, c, pid, logId, ts, ts, ts])
            try db.execute(sql: "INSERT INTO notifications (id, company_id, project_id, kind, details_json, fire_at, created_at, updated_at) VALUES (?, ?, ?, 'depositDue', '{}', '2099-01-01T00:00:00.000Z', ?, ?)", arguments: [UUID().dbKey, c, pid, ts, ts])
        }

        try await repo.softDelete(id: p.id, actor: actor)

        try await db.writer.read { db in
            for table in ["projects", "project_scope_fields", "project_estimate_lines", "project_tasks", "task_checklist_items", "task_assignees", "project_workers",
                          "payment_schedule_items", "payments", "expenses", "receipt_images", "labour_entries", "daily_logs", "photos", "notifications"] {
                let live = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table) WHERE deleted_at IS NULL") ?? -1
                XCTAssertEqual(live, 0, "\(table) still has live rows")
                let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? -1
                XCTAssertGreaterThan(total, 0, "\(table) rows were physically deleted")
            }
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM employees WHERE deleted_at IS NULL"), 1)
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM activity_log WHERE deleted_at IS NULL AND project_id = ?", arguments: [pid]), 2)
        }
        let actions = try await activityActions(p.id)
        XCTAssertEqual(actions, ["projectCreated", "projectDeleted"])
    }
}
