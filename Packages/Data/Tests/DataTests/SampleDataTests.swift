import XCTest
import GRDB
import Domain
@testable import Data

final class SampleDataTests: XCTestCase {
    func testSeedCreatesThreeProjectsAndIsIdempotent() async throws {
        let db = try AppDatabase.inMemory()
        let clock = Clock.fixed(Date(timeIntervalSince1970: 1_790_000_000))
        let setup = try await SampleData.seedIfEmpty(db, clock: clock, today: CalendarDate(clock.now(), timeZone: .gmt))
        XCTAssertEqual(setup.company.name, "Northwind Contracting")
        XCTAssertEqual(setup.owner.displayName, "Duc")
        let projects = try await GRDBProjectRepository(database: db, clock: clock).list(companyId: setup.company.id)
        XCTAssertEqual(Set(projects.map(\.status)), [.inProgress, .awaitingDeposit, .completed])
        XCTAssertEqual(projects.first { $0.status == .inProgress }?.manualProgress, 65)
        XCTAssertEqual(projects.first { $0.status == .inProgress }?.contractValue.storageString, "38000.00")

        let basement = projects.first { $0.status == .inProgress }!
        XCTAssertEqual(basement.scopeFields.count, 6)
        let lines = try await GRDBProjectEstimateRepository(database: db, clock: clock).lines(projectId: basement.id)
        XCTAssertEqual(lines.count, 9)
        let items = try await GRDBPaymentScheduleRepository(database: db, clock: clock).items(projectId: basement.id)
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(try Money.sum(items.map(\.amount), currency: .cad).storageString, "38000.00")
        let kitchen = projects.first { $0.status == .awaitingDeposit }!
        let kitchenItems = try await GRDBPaymentScheduleRepository(database: db, clock: clock).items(projectId: kitchen.id)
        XCTAssertEqual(kitchenItems.count, 1)
        XCTAssertEqual(kitchenItems[0].dueDate, CalendarDate(clock.now(), timeZone: .gmt).adding(days: 7))

        let again = try await SampleData.seedIfEmpty(db, clock: clock, today: CalendarDate(clock.now(), timeZone: .gmt))
        XCTAssertEqual(again.company.id, setup.company.id)
        let count = try await GRDBProjectRepository(database: db, clock: clock).list(companyId: setup.company.id).count
        XCTAssertEqual(count, 3)
    }

    func testSeedMatchesSpecTotals() async throws {
        let db = try AppDatabase.inMemory()
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let today = CalendarDate(storage: "2026-10-03")!
        let setup = try await SampleData.seedIfEmpty(db, clock: .fixed(now), today: today)
        var it = GRDBInsightsRepository(database: db).observeDashboard(companyId: setup.company.id).makeAsyncIterator()
        let snap = try await it.next()!
        let d = DashboardComposer.compose(snap.with(today: today))
        XCTAssertEqual(d.totals.activeJobs, 1)
        XCTAssertEqual(d.totals.outstanding, Money(55_400, .cad))
        XCTAssertEqual(d.totals.collected, Money(26_100, .cad))
        XCTAssertEqual(d.totals.spent, Money(10_685, .cad))
        XCTAssertEqual(d.totals.cashPosition, Money(15_415, .cad))
        XCTAssertEqual(d.attention.map(\.kind), [.paymentRisk, .paymentOverdue, .startsToday])
        let basement = try XCTUnwrap(d.cards.first { $0.project.name == "Basement Renovation" })
        XCTAssertEqual(basement.insights.financials?.cashPosition, Money(-3085, .cad))
        XCTAssertEqual(basement.insights.timeline.daysRemaining, 27)
        XCTAssertEqual(basement.project.startDate, today.adding(days: -18))
        let kitchen = try XCTUnwrap(d.cards.first { $0.project.name == "Kitchen Renovation" })
        XCTAssertEqual(kitchen.project.startDate, today)
        XCTAssertEqual(snap.labourEntries.count, 3)
        XCTAssertEqual(snap.expenses.count, 3)
        XCTAssertEqual(snap.payments.count, 2)
    }

    func testSeedExpensesReceiptsAndCategory() async throws {
        let db = try AppDatabase.inMemory()
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let today = CalendarDate(storage: "2026-10-03")!
        let store = temporaryReceiptStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let setup = try await SampleData.seedIfEmpty(db, clock: .fixed(now), today: today, receiptStore: store, sampleReceipt: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        var it = GRDBExpenseRepository(database: db, clock: .fixed(now), receiptStore: store).observeAll(companyId: setup.company.id).makeAsyncIterator()
        let snap = try await it.next()!
        let list = ExpenseListComposer.compose(snap, filter: ExpenseFilter(), today: today)
        XCTAssertEqual(list.thisMonth, Money(1695, .cad))
        XCTAssertEqual(list.lastMonth, Money(3390, .cad))
        XCTAssertEqual(list.sections.map(\.day.storageString), ["2026-10-01", "2026-09-18", "2026-09-17"])
        XCTAssertEqual(list.rows.compactMap(\.expense.vendorName), ["Drywall", "Lumber — Home Depot", "Dumpster rental"])
        XCTAssertEqual(list.rows.map(\.receiptCount), [0, 2, 1])
        XCTAssertEqual(snap.customCategories.map(\.name), ["Scaffolding"])
        XCTAssertEqual(snap.customCategories.first?.costGroup, .equipment)
        XCTAssertEqual(CategoryRanking.mostUsed(expenses: snap.expenses, customCategories: snap.customCategories),
                       [.standard(.materials), .standard(.wasteDisposal), .standard(.fuel), .standard(.toolPurchase), .standard(.equipmentRental), .standard(.subcontractor)])
        let basementId = snap.projects.first { $0.name == "Basement Renovation" }?.id
        XCTAssertEqual(ExpenseProjectChoice.defaultProject(expenses: snap.expenses, projects: snap.projects), basementId)
        let added = try await db.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM activity_log WHERE action = 'expenseAdded'") ?? 0 }
        XCTAssertEqual(added, 3)
        let page = try XCTUnwrap(list.rows[1].expense.receiptImages.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: page.filePath).path))
    }

    func testSeedRoutesPaymentsAndLabourThroughRepositories() async throws {
        let db = try AppDatabase.inMemory()
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let today = CalendarDate(storage: "2026-10-03")!
        let setup = try await SampleData.seedIfEmpty(db, clock: .fixed(now), today: today)
        let counts = try await db.writer.read { db in
            try Dictionary(uniqueKeysWithValues: Row.fetchAll(db, sql: "SELECT action, COUNT(*) AS n FROM activity_log WHERE action IN ('paymentReceived', 'labourLogged') GROUP BY action")
                .map { (row: Row) -> (String, Int) in (row["action"], row["n"]) })
        }
        XCTAssertEqual(counts, ["paymentReceived": 2, "labourLogged": 3])
        let mikeJSON = try await db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT details_json FROM activity_log WHERE action = 'labourLogged' AND details_json LIKE '%Mike%'")
        }
        XCTAssertEqual(mikeJSON, #"{"currency":"CAD","names":"Mike","people":"1","total":"2000.00","workDate":"2026-09-23"}"#)
        let depositJSON = try await db.writer.read { db in
            try String.fetchOne(db, sql: "SELECT details_json FROM activity_log WHERE action = 'paymentReceived' AND details_json LIKE '%7600.00%'")
        }
        XCTAssertEqual(depositJSON, #"{"amount":"7600.00","currency":"CAD","item":"schedule.row.deposit","method":"eTransfer"}"#)
        var it = GRDBEmployeeRepository(database: db, clock: .fixed(now)).observeAll(companyId: setup.company.id).makeAsyncIterator()
        let crew = try await XCTUnwrapAsync(try await it.next())
        XCTAssertEqual(crew.map(\.name), ["David", "John", "Mike"])
        XCTAssertEqual(crew.map { $0.trade ?? "" }, ["Labourer", "Drywall", "Carpenter"])
        XCTAssertEqual(crew.map { $0.dailyRate?.storageString ?? "" }, ["200.00", "220.00", "250.00"])
        XCTAssertEqual(crew.last?.hourlyRate?.storageString, "31.25")
        XCTAssertEqual(crew.last?.phone, "416-555-0110")
        await XCTAssertEqualAsync(try await GRDBPaymentRepository(database: db, clock: .fixed(now)).lastUsedMethod(companyId: setup.company.id), .eTransfer)
    }
}
