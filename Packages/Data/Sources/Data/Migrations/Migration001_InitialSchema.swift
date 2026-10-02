import Foundation
import GRDB

enum Migration001_InitialSchema {
    private static let common = """
        id TEXT PRIMARY KEY,
        company_id TEXT NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        sync_state TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced')),
        """

    private static func fk(_ column: String, _ table: String) -> String {
        "FOREIGN KEY (\(column), company_id) REFERENCES \(table)(id, company_id) ON DELETE RESTRICT"
    }

    private static func projectScopedFK(_ column: String, _ table: String) -> String {
        "FOREIGN KEY (\(column), project_id, company_id) REFERENCES \(table)(id, project_id, company_id) ON DELETE RESTRICT"
    }

    static func apply(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE companies (
                id TEXT PRIMARY KEY,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                deleted_at TEXT,
                sync_state TEXT NOT NULL DEFAULT 'pending' CHECK (sync_state IN ('pending', 'synced')),
                name TEXT NOT NULL,
                currency_code TEXT NOT NULL CHECK (currency_code IN ('CAD', 'USD'))
            );

            CREATE TABLE users (
                \(common)
                display_name TEXT NOT NULL,
                email TEXT,
                role TEXT NOT NULL DEFAULT 'owner' CHECK (role IN ('owner')),
                auth_user_id TEXT,
                UNIQUE (id, company_id)
            );
            CREATE INDEX idx_users_company ON users(company_id);
            CREATE UNIQUE INDEX uq_users_auth ON users(auth_user_id) WHERE deleted_at IS NULL AND auth_user_id IS NOT NULL;

            CREATE TABLE customers (
                \(common)
                name TEXT NOT NULL,
                phone TEXT,
                email TEXT,
                preferred_contact TEXT CHECK (preferred_contact IN ('phone', 'text', 'email')),
                company_name TEXT,
                secondary_contact TEXT,
                notes TEXT,
                UNIQUE (id, company_id)
            );
            CREATE INDEX idx_customers_company ON customers(company_id);
            CREATE INDEX idx_customers_company_name ON customers(company_id, name);

            CREATE TABLE projects (
                \(common)
                customer_id TEXT NOT NULL,
                name TEXT NOT NULL,
                job_type TEXT NOT NULL CHECK (job_type IN ('generalRenovation', 'basementRenovation', 'kitchen', 'bathroom', 'landscaping', 'roofing', 'plumbing', 'electrical', 'hvac', 'flooring', 'painting', 'drywall', 'concrete', 'deckFence', 'framing', 'windowsDoors', 'exterior', 'demolition', 'commercial', 'other')),
                custom_job_type TEXT,
                status TEXT NOT NULL CHECK (status IN ('estimate', 'awaitingApproval', 'awaitingDeposit', 'scheduled', 'inProgress', 'onHold', 'waitingForInspection', 'waitingForMaterial', 'waitingForClient', 'completed', 'awaitingFinalPayment', 'closed', 'cancelled')),
                address_line TEXT NOT NULL,
                unit TEXT,
                city TEXT,
                region TEXT,
                postal_code TEXT,
                scope_description TEXT,
                start_date TEXT,
                estimated_completion_date TEXT,
                working_days INTEGER,
                hours_per_day TEXT,
                workers_per_day INTEGER,
                contract_value TEXT NOT NULL DEFAULT '0.00',
                manual_progress INTEGER CHECK (manual_progress BETWEEN 0 AND 100),
                deposit_required_to_start INTEGER NOT NULL DEFAULT 0,
                UNIQUE (id, company_id),
                \(fk("customer_id", "customers"))
            );
            CREATE INDEX idx_projects_company ON projects(company_id);
            CREATE INDEX idx_projects_company_status ON projects(company_id, status);
            CREATE INDEX idx_projects_customer ON projects(customer_id);

            CREATE TABLE project_scope_fields (
                \(common)
                project_id TEXT NOT NULL,
                field_key TEXT NOT NULL CHECK (length(field_key) > 0),
                value_text TEXT NOT NULL,
                sort_order INTEGER NOT NULL,
                UNIQUE (id, company_id),
                \(fk("project_id", "projects"))
            );
            CREATE INDEX idx_project_scope_fields_company ON project_scope_fields(company_id);
            CREATE INDEX idx_project_scope_fields_project ON project_scope_fields(project_id);
            CREATE UNIQUE INDEX uq_project_scope_fields_key ON project_scope_fields(project_id, field_key) WHERE deleted_at IS NULL;

            CREATE TABLE project_estimate_lines (
                \(common)
                project_id TEXT NOT NULL,
                cost_group TEXT NOT NULL CHECK (cost_group IN ('material', 'labour', 'subcontractor', 'equipment', 'permit', 'other')),
                label TEXT NOT NULL,
                amount TEXT NOT NULL,
                quantity TEXT,
                unit_rate TEXT,
                sort_order INTEGER NOT NULL,
                UNIQUE (id, company_id),
                \(fk("project_id", "projects"))
            );
            CREATE INDEX idx_project_estimate_lines_company ON project_estimate_lines(company_id);
            CREATE INDEX idx_project_estimate_lines_project_group ON project_estimate_lines(project_id, cost_group);

            CREATE TABLE employees (
                \(common)
                name TEXT NOT NULL,
                phone TEXT,
                role TEXT,
                trade TEXT,
                hourly_rate TEXT,
                daily_rate TEXT,
                certifications TEXT,
                emergency_contact TEXT,
                notes TEXT,
                UNIQUE (id, company_id)
            );
            CREATE INDEX idx_employees_company ON employees(company_id);
            CREATE INDEX idx_employees_company_name ON employees(company_id, name);

            CREATE TABLE project_tasks (
                \(common)
                project_id TEXT NOT NULL,
                name TEXT NOT NULL,
                status TEXT NOT NULL CHECK (status IN ('notStarted', 'scheduled', 'inProgress', 'blocked', 'waiting', 'completed')),
                start_date TEXT,
                due_date TEXT,
                notes TEXT,
                sort_order INTEGER NOT NULL,
                UNIQUE (id, company_id),
                \(fk("project_id", "projects"))
            );
            CREATE INDEX idx_project_tasks_company ON project_tasks(company_id);
            CREATE INDEX idx_project_tasks_project_order ON project_tasks(project_id, sort_order);
            CREATE INDEX idx_project_tasks_company_due ON project_tasks(company_id, due_date);

            CREATE TABLE task_checklist_items (
                \(common)
                task_id TEXT NOT NULL,
                title TEXT NOT NULL,
                is_done INTEGER NOT NULL DEFAULT 0,
                sort_order INTEGER NOT NULL,
                UNIQUE (id, company_id),
                \(fk("task_id", "project_tasks"))
            );
            CREATE INDEX idx_task_checklist_items_company ON task_checklist_items(company_id);
            CREATE INDEX idx_task_checklist_items_task ON task_checklist_items(task_id);

            CREATE TABLE task_assignees (
                \(common)
                task_id TEXT NOT NULL,
                employee_id TEXT NOT NULL,
                UNIQUE (id, company_id),
                \(fk("task_id", "project_tasks")),
                \(fk("employee_id", "employees"))
            );
            CREATE INDEX idx_task_assignees_company ON task_assignees(company_id);
            CREATE INDEX idx_task_assignees_task ON task_assignees(task_id);
            CREATE INDEX idx_task_assignees_employee ON task_assignees(employee_id);
            CREATE UNIQUE INDEX uq_task_assignees_pair ON task_assignees(task_id, employee_id) WHERE deleted_at IS NULL;

            CREATE TABLE project_workers (
                \(common)
                project_id TEXT NOT NULL,
                employee_id TEXT NOT NULL,
                work_date TEXT NOT NULL,
                UNIQUE (id, company_id),
                \(fk("project_id", "projects")),
                \(fk("employee_id", "employees"))
            );
            CREATE INDEX idx_project_workers_company ON project_workers(company_id);
            CREATE INDEX idx_project_workers_project ON project_workers(project_id);
            CREATE INDEX idx_project_workers_employee ON project_workers(employee_id);
            CREATE INDEX idx_project_workers_company_date ON project_workers(company_id, work_date);
            CREATE UNIQUE INDEX uq_project_workers_day ON project_workers(project_id, employee_id, work_date) WHERE deleted_at IS NULL;

            CREATE TABLE payment_schedule_items (
                \(common)
                project_id TEXT NOT NULL,
                label TEXT NOT NULL,
                amount TEXT NOT NULL,
                percentage TEXT,
                due_date TEXT,
                trigger_text TEXT,
                is_deposit INTEGER NOT NULL DEFAULT 0,
                notes TEXT,
                sort_order INTEGER NOT NULL,
                UNIQUE (id, company_id),
                UNIQUE (id, project_id, company_id),
                \(fk("project_id", "projects"))
            );
            CREATE INDEX idx_payment_schedule_items_company ON payment_schedule_items(company_id);
            CREATE INDEX idx_payment_schedule_items_project_order ON payment_schedule_items(project_id, sort_order);
            CREATE INDEX idx_payment_schedule_items_company_due ON payment_schedule_items(company_id, due_date);

            CREATE TABLE payments (
                \(common)
                project_id TEXT NOT NULL,
                schedule_item_id TEXT,
                amount TEXT NOT NULL,
                paid_on TEXT NOT NULL,
                method TEXT NOT NULL CHECK (method IN ('cash', 'cheque', 'eTransfer', 'creditCard', 'bankTransfer', 'other')),
                notes TEXT,
                UNIQUE (id, company_id),
                \(fk("project_id", "projects")),
                \(projectScopedFK("schedule_item_id", "payment_schedule_items"))
            );
            CREATE INDEX idx_payments_company ON payments(company_id);
            CREATE INDEX idx_payments_project_date ON payments(project_id, paid_on);
            CREATE INDEX idx_payments_schedule_item ON payments(schedule_item_id);

            CREATE TABLE custom_expense_categories (
                \(common)
                name TEXT NOT NULL,
                cost_group TEXT NOT NULL DEFAULT 'other' CHECK (cost_group IN ('material', 'labour', 'subcontractor', 'equipment', 'permit', 'other')),
                UNIQUE (id, company_id)
            );
            CREATE INDEX idx_custom_expense_categories_company ON custom_expense_categories(company_id);
            CREATE UNIQUE INDEX uq_custom_expense_categories_name ON custom_expense_categories(company_id, name) WHERE deleted_at IS NULL;

            CREATE TABLE expenses (
                \(common)
                project_id TEXT NOT NULL,
                category TEXT NOT NULL CHECK (category IN ('materials', 'labour', 'subcontractor', 'equipmentRental', 'toolPurchase', 'permit', 'inspection', 'delivery', 'fuel', 'wasteDisposal', 'parking', 'office', 'other', 'custom')),
                custom_category_id TEXT,
                cost_group TEXT NOT NULL CHECK (cost_group IN ('material', 'labour', 'subcontractor', 'equipment', 'permit', 'other')),
                vendor_name TEXT,
                amount TEXT NOT NULL,
                tax TEXT NOT NULL DEFAULT '0.00',
                spent_on TEXT NOT NULL,
                payment_method TEXT CHECK (payment_method IN ('cash', 'cheque', 'eTransfer', 'creditCard', 'bankTransfer', 'other')),
                notes TEXT,
                UNIQUE (id, company_id),
                CHECK ((category = 'custom') = (custom_category_id IS NOT NULL)),
                \(fk("project_id", "projects")),
                \(fk("custom_category_id", "custom_expense_categories"))
            );
            CREATE INDEX idx_expenses_company ON expenses(company_id);
            CREATE INDEX idx_expenses_project_date ON expenses(project_id, spent_on);
            CREATE INDEX idx_expenses_company_date ON expenses(company_id, spent_on);
            CREATE INDEX idx_expenses_custom_category ON expenses(custom_category_id);

            CREATE TABLE receipt_images (
                \(common)
                expense_id TEXT NOT NULL,
                file_path TEXT NOT NULL,
                remote_path TEXT,
                page_index INTEGER NOT NULL,
                UNIQUE (id, company_id),
                \(fk("expense_id", "expenses"))
            );
            CREATE INDEX idx_receipt_images_company ON receipt_images(company_id);
            CREATE INDEX idx_receipt_images_expense ON receipt_images(expense_id);
            CREATE UNIQUE INDEX uq_receipt_images_page ON receipt_images(expense_id, page_index) WHERE deleted_at IS NULL;

            CREATE TABLE labour_entries (
                \(common)
                project_id TEXT NOT NULL,
                employee_id TEXT NOT NULL,
                work_date TEXT NOT NULL,
                days TEXT NOT NULL,
                daily_rate TEXT NOT NULL,
                notes TEXT,
                UNIQUE (id, company_id),
                \(fk("project_id", "projects")),
                \(fk("employee_id", "employees"))
            );
            CREATE INDEX idx_labour_entries_company ON labour_entries(company_id);
            CREATE INDEX idx_labour_entries_project_date ON labour_entries(project_id, work_date);
            CREATE INDEX idx_labour_entries_employee_date ON labour_entries(employee_id, work_date);

            CREATE TABLE daily_logs (
                \(common)
                project_id TEXT NOT NULL,
                log_date TEXT NOT NULL,
                workers_onsite INTEGER,
                weather TEXT,
                work_completed TEXT,
                material_delivered TEXT,
                problems TEXT,
                tomorrow_plan TEXT,
                UNIQUE (id, company_id),
                UNIQUE (id, project_id, company_id),
                \(fk("project_id", "projects"))
            );
            CREATE INDEX idx_daily_logs_company ON daily_logs(company_id);
            CREATE INDEX idx_daily_logs_project ON daily_logs(project_id);
            CREATE UNIQUE INDEX uq_daily_logs_date ON daily_logs(project_id, log_date) WHERE deleted_at IS NULL;

            CREATE TABLE photos (
                \(common)
                project_id TEXT NOT NULL,
                daily_log_id TEXT,
                category TEXT NOT NULL CHECK (category IN ('before', 'progress', 'issues', 'inspection', 'completed', 'receipts')),
                taken_at TEXT NOT NULL,
                latitude REAL,
                longitude REAL,
                file_path TEXT NOT NULL,
                remote_path TEXT,
                caption TEXT,
                UNIQUE (id, company_id),
                \(fk("project_id", "projects")),
                \(projectScopedFK("daily_log_id", "daily_logs"))
            );
            CREATE INDEX idx_photos_company ON photos(company_id);
            CREATE INDEX idx_photos_project_taken ON photos(project_id, taken_at);
            CREATE INDEX idx_photos_daily_log ON photos(daily_log_id);

            CREATE TABLE activity_log (
                \(common)
                user_id TEXT,
                actor_name TEXT NOT NULL,
                action TEXT NOT NULL,
                entity_type TEXT NOT NULL,
                entity_id TEXT NOT NULL,
                project_id TEXT,
                details_json TEXT NOT NULL,
                occurred_at TEXT NOT NULL,
                UNIQUE (id, company_id),
                \(fk("user_id", "users")),
                \(fk("project_id", "projects"))
            );
            CREATE INDEX idx_activity_log_company ON activity_log(company_id);
            CREATE INDEX idx_activity_log_project_time ON activity_log(project_id, occurred_at);
            CREATE INDEX idx_activity_log_company_time ON activity_log(company_id, occurred_at);
            CREATE INDEX idx_activity_log_user ON activity_log(user_id);

            CREATE TABLE notifications (
                \(common)
                project_id TEXT,
                kind TEXT NOT NULL,
                entity_type TEXT,
                entity_id TEXT,
                details_json TEXT NOT NULL,
                fire_at TEXT NOT NULL,
                read_at TEXT,
                UNIQUE (id, company_id),
                \(fk("project_id", "projects"))
            );
            CREATE INDEX idx_notifications_company ON notifications(company_id);
            CREATE INDEX idx_notifications_company_fire ON notifications(company_id, fire_at);
            CREATE INDEX idx_notifications_project ON notifications(project_id);
            """)
    }
}
