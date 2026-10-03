import XCTest
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
}
