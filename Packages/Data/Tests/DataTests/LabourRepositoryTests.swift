// Packages/Data/Tests/DataTests/LabourRepositoryTests.swift
import XCTest
import GRDB
import Domain
@testable import Data

final class LabourRepositoryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let today = CalendarDate(storage: "2026-10-03")!
    var db: AppDatabase!
    var f: Fixture!
    var crew: GRDBEmployeeRepository!
    var repo: GRDBLabourRepository!
    var mike: Employee!
    var john: Employee!

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        f = try await makeFixture(db, now: now)
        crew = GRDBEmployeeRepository(database: db, clock: .fixed(now))
        repo = GRDBLabourRepository(database: db, clock: .fixed(now))
        mike = person("Mike", "250.00")
        john = person("John", "333.33")
        try await crew.create(mike)
        try await crew.create(john)
    }

    func person(_ name: String, _ rate: String) -> Employee {
        Employee(id: UUID(), companyId: f.companyId, name: name, phone: nil, role: nil, trade: nil, hourlyRate: nil, dailyRate: Money(storage: rate, currency: .cad),
                 certifications: nil, emergencyContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
    }
    func entry(_ e: Employee, days: String, rate: String, project: Project? = nil, id: UUID = UUID()) -> LabourEntry {
        LabourEntry(id: id, companyId: f.companyId, projectId: (project ?? f.project).id, employeeId: e.id, workDate: today, days: Decimal(string: days)!,
                    dailyRate: Money(storage: rate, currency: .cad)!, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
    }
    func activities() async throws -> [(action: String, details: String)] {
        try await db.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT action, details_json FROM activity_log WHERE entity_type = 'labour_entry' ORDER BY rowid").map { ($0["action"], $0["details_json"]) }
        }
    }
    func entryRows() async throws -> Int {
        try await db.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM labour_entries") ?? 0 }
    }
    func snapshot() async throws -> ProjectLabourSnapshot {
        var it = repo.observeProject(id: f.project.id).makeAsyncIterator()
        let value = try await it.next()
        return try XCTUnwrap(value ?? nil)
    }
    func labourActual() async throws -> Money? {
        var it = GRDBInsightsRepository(database: db).observeProject(id: f.project.id).makeAsyncIterator()
        let value = try await it.next()
        let snap = try XCTUnwrap(value ?? nil)
        return ProjectInsightsComposer.compose(snap.with(today: today)).financials?.actualByGroup[.labour]
    }

    func testCreateBatchWritesOneActivity() async throws {
        try await repo.create([entry(mike, days: "1", rate: "250.00"), entry(john, days: "0.5", rate: "333.33")], actor: f.actor)
        await XCTAssertEqualAsync(try await self.entryRows(), 2)
        let a = try await activities()
        XCTAssertEqual(a.map(\.action), ["labourLogged"])
        XCTAssertEqual(a[0].details, #"{"currency":"CAD","names":"Mike, John","people":"2","total":"416.67","workDate":"2026-10-03"}"#)
        await XCTAssertEqualAsync(try await self.snapshot().entries.count, 2)
        await XCTAssertEqualAsync(try await self.labourActual(), Money(storage: "416.67", currency: .cad))
    }

    func testBatchWithDeletedEmployeeWritesNothing() async throws {
        try await crew.softDelete(id: john.id)
        await XCTAssertThrowsErrorAsync(try await self.repo.create([self.entry(self.mike, days: "1", rate: "250.00"), self.entry(self.john, days: "1", rate: "333.33")], actor: self.f.actor)) {
            XCTAssertEqual($0 as? DomainError, .notFound)
        }
        await XCTAssertEqualAsync(try await self.entryRows(), 0)
        await XCTAssertEqualAsync(try await self.activities().count, 0)
    }

    func testInvalidBatches() async throws {
        await XCTAssertThrowsErrorAsync(try await self.repo.create([], actor: self.f.actor)) { XCTAssertEqual($0 as? DomainError, .incompleteLabour) }
        await XCTAssertThrowsErrorAsync(try await self.repo.create([self.entry(self.mike, days: "0", rate: "250.00")], actor: self.f.actor)) {
            XCTAssertEqual($0 as? DomainError, .invalidLabourDays)
        }
        let p = f.project
        let other = Project(id: UUID(), companyId: p.companyId, customerId: p.customerId, name: "Q", jobType: p.jobType, customJobType: nil, status: .inProgress,
                            address: p.address, scopeDescription: nil, scopeFields: [], startDate: nil, estimatedCompletionDate: nil, workingDays: nil, hoursPerDay: nil,
                            workersPerDay: nil, contractValue: Money(1, .cad), manualProgress: nil, depositRequiredToStart: false, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBProjectRepository(database: db, clock: .fixed(now)).save(other, actor: f.actor)
        await XCTAssertThrowsErrorAsync(try await self.repo.create([self.entry(self.mike, days: "1", rate: "250.00"), self.entry(self.john, days: "1", rate: "1.00", project: other)], actor: self.f.actor)) {
            XCTAssertEqual($0 as? DataError, .scopeMismatch)
        }
        await XCTAssertEqualAsync(try await self.entryRows(), 0)
    }

    func testUpdateDaysNoOpAndPersonLocked() async throws {
        let e = entry(mike, days: "1", rate: "250.00")
        try await repo.create([e], actor: f.actor)
        let stored = try await XCTUnwrapAsync(try await repo.get(id: e.id))
        let later = GRDBLabourRepository(database: db, clock: .fixed(now.addingTimeInterval(60)))
        try await later.update(stored, actor: f.actor)
        await XCTAssertEqualAsync(try await self.activities().map(\.action), ["labourLogged"])
        var longer = stored
        longer.days = Decimal(string: "1.5")!
        try await later.update(longer, actor: f.actor)
        let a = try await activities()
        XCTAssertEqual(a.map(\.action), ["labourLogged", "labourUpdated"])
        XCTAssertEqual(a[1].details, #"{"currency":"CAD","from":"250.00","names":"Mike","people":"1","total":"375.00","workDate":"2026-10-03"}"#)
        await XCTAssertEqualAsync(try await self.repo.get(id: e.id)?.cost, Money(375, .cad))
        let swapped = entry(john, days: "1.5", rate: "250.00", id: e.id)
        await XCTAssertThrowsErrorAsync(try await self.repo.update(swapped, actor: self.f.actor)) { XCTAssertEqual($0 as? DataError, .scopeMismatch) }
    }

    func testEmployeeRateChangeKeepsEntrySnapshot() async throws {
        let e = entry(mike, days: "2", rate: "250.00")
        try await repo.create([e], actor: f.actor)
        var raised = mike!
        raised.dailyRate = Money(300, .cad)
        try await crew.update(raised)
        await XCTAssertEqualAsync(try await self.repo.get(id: e.id)?.dailyRate, Money(250, .cad))
        await XCTAssertEqualAsync(try await self.labourActual(), Money(500, .cad))
    }

    func testDeletedEmployeeKeepsHistory() async throws {
        let e = entry(mike, days: "1", rate: "250.00")
        try await repo.create([e], actor: f.actor)
        try await crew.softDelete(id: mike.id)
        let snap = try await snapshot()
        XCTAssertEqual(snap.entries.map(\.id), [e.id])
        let list = LabourListComposer.compose(entries: snap.entries, employees: snap.employees, currency: snap.currency)
        XCTAssertEqual(list.rows.map(\.employeeName), ["Mike"])
        await XCTAssertEqualAsync(try await self.labourActual(), Money(250, .cad))
        var fixed = try await XCTUnwrapAsync(try await repo.get(id: e.id))
        fixed.days = 2
        try await repo.update(fixed, actor: f.actor)                                  // history stays editable
        await XCTAssertEqualAsync(try await self.labourActual(), Money(500, .cad))
    }

    func testSoftDeleteEntry() async throws {
        let e = entry(mike, days: "1", rate: "250.00")
        try await repo.create([e], actor: f.actor)
        try await repo.softDelete(id: e.id, actor: f.actor)
        await XCTAssertNilAsync(try await self.repo.get(id: e.id))
        await XCTAssertEqualAsync(try await self.snapshot().entries.count, 0)
        let a = try await activities()
        XCTAssertEqual(a.map(\.action), ["labourLogged", "labourDeleted"])
        XCTAssertEqual(a[1].details, #"{"currency":"CAD","names":"Mike","people":"1","total":"250.00","workDate":"2026-10-03"}"#)
        await XCTAssertThrowsErrorAsync(try await self.repo.softDelete(id: e.id, actor: self.f.actor)) { XCTAssertEqual($0 as? DomainError, .notFound) }
    }
}
