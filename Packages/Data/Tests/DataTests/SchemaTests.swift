import XCTest
import GRDB
@testable import Data

final class SchemaTests: XCTestCase {
    func testMigrationCreatesAllTables() throws {
        let db = try AppDatabase.inMemory()
        let tables = try db.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%' ORDER BY name")
        }
        XCTAssertEqual(tables, [
            "activity_log", "companies", "custom_expense_categories", "customers", "daily_logs", "employees", "expenses",
            "labour_entries", "notifications", "payment_schedule_items", "payments", "photos", "project_estimate_lines",
            "project_scope_fields", "project_tasks", "project_workers", "projects", "receipt_images", "task_assignees",
            "task_checklist_items", "users",
        ])
    }

    func testCommonColumnsOnEveryTable() throws {
        let db = try AppDatabase.inMemory()
        try db.writer.read { db in
            let tables = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'")
            for table in tables {
                let columns = try db.columns(in: table).map(\.name)
                for required in ["id", "created_at", "updated_at", "deleted_at", "sync_state"] {
                    XCTAssertTrue(columns.contains(required), "\(table) missing \(required)")
                }
                if table == "companies" {
                    XCTAssertFalse(columns.contains("company_id"))
                } else {
                    XCTAssertTrue(columns.contains("company_id"), "\(table) missing company_id")
                }
            }
        }
    }

    func testPaymentsHaveCompositeForeignKeys() throws {
        let db = try AppDatabase.inMemory()
        try db.writer.read { db in
            let fks = try db.foreignKeys(on: "payments")
            let toProjects = fks.first { $0.destinationTable == "projects" }
            XCTAssertEqual(toProjects?.mapping.map(\.origin), ["project_id", "company_id"])
            let toItems = fks.first { $0.destinationTable == "payment_schedule_items" }
            XCTAssertEqual(toItems?.mapping.map(\.origin), ["schedule_item_id", "project_id", "company_id"])
            let photoFks = try db.foreignKeys(on: "photos")
            XCTAssertEqual(photoFks.first { $0.destinationTable == "daily_logs" }?.mapping.map(\.origin), ["daily_log_id", "project_id", "company_id"])
        }
    }

    func testPartialUniqueIndexesAndFullFKTargets() throws {
        let db = try AppDatabase.inMemory()
        try db.writer.read { db in
            let partial = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND sql LIKE '%WHERE deleted_at IS NULL%' ORDER BY name")
            XCTAssertEqual(partial, [
                "uq_custom_expense_categories_name", "uq_daily_logs_date", "uq_project_scope_fields_key", "uq_project_workers_day",
                "uq_receipt_images_page", "uq_task_assignees_pair", "uq_users_auth",
            ])
            // FK targets are full unique constraints (no WHERE).
            let projectsSQL = try String.fetchOne(db, sql: "SELECT sql FROM sqlite_master WHERE name = 'projects'") ?? ""
            XCTAssertTrue(projectsSQL.contains("UNIQUE (id, company_id)"))
            let itemsSQL = try String.fetchOne(db, sql: "SELECT sql FROM sqlite_master WHERE name = 'payment_schedule_items'") ?? ""
            XCTAssertTrue(itemsSQL.contains("UNIQUE (id, project_id, company_id)"))
        }
    }

    func testForeignKeysEnabled() throws {
        let db = try AppDatabase.inMemory()
        let enabled = try db.writer.read { try Bool.fetchOne($0, sql: "PRAGMA foreign_keys") }
        XCTAssertEqual(enabled, true)
    }

    func testTimestampsRoundTrip() {
        let date = Date(timeIntervalSince1970: 1_790_000_000.25)
        let text = Timestamps.string(date)
        XCTAssertEqual(text, "2026-09-21T14:13:20.250Z")
        XCTAssertEqual(Timestamps.date(text), date)
        XCTAssertNil(Timestamps.date("yesterday"))
    }
}
