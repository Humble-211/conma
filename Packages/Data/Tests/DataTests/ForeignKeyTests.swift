import XCTest
import GRDB
@testable import Data

final class ForeignKeyTests: XCTestCase {
    var db: AppDatabase!
    let now = "2026-10-05T12:00:00.000Z"
    let companyA = "aaaaaaaa-0000-0000-0000-000000000001"
    let companyB = "bbbbbbbb-0000-0000-0000-000000000001"
    let customerA = "aaaaaaaa-0000-0000-0000-00000000c001"
    let projectA = "aaaaaaaa-0000-0000-0000-00000000a001"
    let projectA2 = "aaaaaaaa-0000-0000-0000-00000000a002"
    let itemA = "aaaaaaaa-0000-0000-0000-00000000e001"
    let logA = "aaaaaaaa-0000-0000-0000-00000000d001"

    override func setUpWithError() throws {
        db = try AppDatabase.inMemory()
        try db.writer.write { db in
            for (id, name) in [(companyA, "A"), (companyB, "B")] {
                try db.execute(sql: "INSERT INTO companies (id, name, currency_code, created_at, updated_at) VALUES (?, ?, 'CAD', ?, ?)", arguments: [id, name, now, now])
            }
            try db.execute(sql: "INSERT INTO customers (id, company_id, name, created_at, updated_at) VALUES (?, ?, 'Ann', ?, ?)", arguments: [customerA, companyA, now, now])
            for pid in [projectA, projectA2] {
                try db.execute(sql: """
                    INSERT INTO projects (id, company_id, customer_id, name, job_type, status, address_line, contract_value, deposit_required_to_start, created_at, updated_at)
                    VALUES (?, ?, ?, 'P', 'kitchen', 'inProgress', '1 Main', '0.00', 0, ?, ?)
                    """, arguments: [pid, companyA, customerA, now, now])
            }
            try db.execute(sql: "INSERT INTO payment_schedule_items (id, company_id, project_id, label, amount, is_deposit, sort_order, created_at, updated_at) VALUES (?, ?, ?, 'Deposit', '100.00', 1, 0, ?, ?)", arguments: [itemA, companyA, projectA, now, now])
            try db.execute(sql: "INSERT INTO daily_logs (id, company_id, project_id, log_date, created_at, updated_at) VALUES (?, ?, ?, '2026-10-05', ?, ?)", arguments: [logA, companyA, projectA, now, now])
        }
    }

    private func assertForeignKeyFailure(_ body: @escaping (Database) throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try db.writer.write(body), file: file, line: line) { error in
            XCTAssertEqual((error as? DatabaseError)?.extendedResultCode, .SQLITE_CONSTRAINT_FOREIGNKEY, "\(error)", file: file, line: line)
        }
    }

    func testCrossCompanyProjectReferenceRejected() {
        assertForeignKeyFailure { db in
            try db.execute(sql: "INSERT INTO project_tasks (id, company_id, project_id, name, status, sort_order, created_at, updated_at) VALUES ('t1', ?, ?, 'Framing', 'notStarted', 0, ?, ?)",
                           arguments: [self.companyB, self.projectA, self.now, self.now])
        }
    }

    func testCrossProjectScheduleItemRejectedAndNullAccepted() throws {
        assertForeignKeyFailure { db in
            try db.execute(sql: "INSERT INTO payments (id, company_id, project_id, schedule_item_id, amount, paid_on, method, created_at, updated_at) VALUES ('p1', ?, ?, ?, '50.00', '2026-10-05', 'cash', ?, ?)",
                           arguments: [self.companyA, self.projectA2, self.itemA, self.now, self.now])
        }
        try db.writer.write { db in
            try db.execute(sql: "INSERT INTO payments (id, company_id, project_id, schedule_item_id, amount, paid_on, method, created_at, updated_at) VALUES ('p2', ?, ?, NULL, '50.00', '2026-10-05', 'cash', ?, ?)",
                           arguments: [self.companyA, self.projectA2, self.now, self.now])
            try db.execute(sql: "INSERT INTO payments (id, company_id, project_id, schedule_item_id, amount, paid_on, method, created_at, updated_at) VALUES ('p3', ?, ?, ?, '50.00', '2026-10-05', 'cash', ?, ?)",
                           arguments: [self.companyA, self.projectA, self.itemA, self.now, self.now])
        }
    }

    func testCrossProjectDailyLogRejectedAndNullAccepted() throws {
        assertForeignKeyFailure { db in
            try db.execute(sql: "INSERT INTO photos (id, company_id, project_id, daily_log_id, category, taken_at, file_path, created_at, updated_at) VALUES ('ph1', ?, ?, ?, 'progress', ?, 'a.jpg', ?, ?)",
                           arguments: [self.companyA, self.projectA2, self.logA, self.now, self.now, self.now])
        }
        try db.writer.write { db in
            try db.execute(sql: "INSERT INTO photos (id, company_id, project_id, daily_log_id, category, taken_at, file_path, created_at, updated_at) VALUES ('ph2', ?, ?, NULL, 'progress', ?, 'b.jpg', ?, ?)",
                           arguments: [self.companyA, self.projectA2, self.now, self.now, self.now])
        }
    }

    func testCheckConstraintsRejectUnknownEnumValues() {
        XCTAssertThrowsError(try db.writer.write { db in
            try db.execute(sql: "UPDATE projects SET job_type = 'sauna' WHERE id = ?", arguments: [self.projectA])
        }) { XCTAssertEqual(($0 as? DatabaseError)?.resultCode, .SQLITE_CONSTRAINT) }
        XCTAssertThrowsError(try db.writer.write { db in
            try db.execute(sql: "INSERT INTO expenses (id, company_id, project_id, category, cost_group, amount, tax, spent_on, created_at, updated_at) VALUES ('e1', ?, ?, 'materials', 'snacks', '1.00', '0.00', '2026-10-05', ?, ?)",
                           arguments: [self.companyA, self.projectA, self.now, self.now])
        }) { XCTAssertEqual(($0 as? DatabaseError)?.resultCode, .SQLITE_CONSTRAINT) }
    }

    func testPartialUniqueAllowsReuseAfterSoftDelete() throws {
        try db.writer.write { db in
            try db.execute(sql: "INSERT INTO custom_expense_categories (id, company_id, name, cost_group, created_at, updated_at, deleted_at) VALUES ('c1', ?, 'Scaffolding', 'equipment', ?, ?, ?)", arguments: [self.companyA, self.now, self.now, self.now])
            try db.execute(sql: "INSERT INTO custom_expense_categories (id, company_id, name, cost_group, created_at, updated_at) VALUES ('c2', ?, 'Scaffolding', 'equipment', ?, ?)", arguments: [self.companyA, self.now, self.now])
        }
        XCTAssertThrowsError(try db.writer.write { db in
            try db.execute(sql: "INSERT INTO custom_expense_categories (id, company_id, name, cost_group, created_at, updated_at) VALUES ('c3', ?, 'Scaffolding', 'equipment', ?, ?)", arguments: [self.companyA, self.now, self.now])
        })
    }
}
