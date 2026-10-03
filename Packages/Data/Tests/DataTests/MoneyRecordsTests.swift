import XCTest
import GRDB
import Domain
@testable import Data

final class MoneyRecordsTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    var db: AppDatabase!
    var companyId: UUID!
    var project: Project!
    var customer: Customer!

    override func setUp() async throws {
        db = try AppDatabase.inMemory()
        let company = Company(id: UUID(), name: "N", currencyCode: .cad, createdAt: now, updatedAt: now, deletedAt: nil)
        let owner = User(id: UUID(), companyId: company.id, displayName: "Duc", email: nil, role: .owner, authUserId: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBCompanyRepository(database: db, clock: .fixed(now)).create(company: company, owner: owner)
        companyId = company.id
        customer = Customer(id: UUID(), companyId: companyId, name: "Ann", phone: nil, email: nil, preferredContact: nil, companyName: nil, secondaryContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBCustomerRepository(database: db, clock: .fixed(now)).save(customer)
        project = Project(id: UUID(), companyId: companyId, customerId: customer.id, name: "P", jobType: .kitchen, customJobType: nil, status: .inProgress, address: Address(line: "1", unit: nil, city: nil, region: nil, postalCode: nil), scopeDescription: nil, scopeFields: [], startDate: nil, estimatedCompletionDate: nil, workingDays: nil, hoursPerDay: nil, workersPerDay: nil, contractValue: Money(1000, .cad), manualProgress: nil, depositRequiredToStart: false, createdAt: now, updatedAt: now, deletedAt: nil)
        try await GRDBProjectRepository(database: db, clock: .fixed(now)).save(project, actor: ActivityActor(userId: owner.id, name: "Duc"))
    }

    func testExpenseRoundTrip() async throws {
        let e = Expense(id: UUID(), companyId: companyId, projectId: project.id, category: .materials, customCategoryId: nil, costGroup: .material, vendorName: "Home Depot", amount: Money(Decimal(string: "2400.00")!, .cad), tax: Money(Decimal(string: "312.00")!, .cad), spentOn: CalendarDate(storage: "2026-10-01")!, paymentMethod: .creditCard, notes: nil, receiptImages: [], createdAt: now, updatedAt: now, deletedAt: nil)
        try await db.writer.write { db in try ExpenseRecord(e).insert(db) }
        let back = try await db.writer.read { db in try ExpenseRecord.fetchLive(db, projectId: self.project.id.dbKey, currency: .cad) }
        XCTAssertEqual(back, [e])
        XCTAssertEqual(try back[0].totalCost(), Money(Decimal(string: "2712.00")!, .cad))
    }

    func testLabourEntryRoundTripNeedsEmployee() async throws {
        let emp = Employee(id: UUID(), companyId: companyId, name: "Mike", phone: nil, role: nil, trade: nil, hourlyRate: nil, dailyRate: Money(250, .cad), certifications: nil, emergencyContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        let l = LabourEntry(id: UUID(), companyId: companyId, projectId: project.id, employeeId: emp.id, workDate: CalendarDate(storage: "2026-10-01")!, days: Decimal(string: "1.5")!, dailyRate: Money(250, .cad), notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        try await db.writer.write { db in try EmployeeRecord(emp).insert(db); try LabourEntryRecord(l).insert(db) }
        let back = try await db.writer.read { db in try LabourEntryRecord.fetchLive(db, projectId: self.project.id.dbKey, currency: .cad) }
        XCTAssertEqual(back, [l])
        XCTAssertEqual(back[0].cost, Money(375, .cad))
    }

    func testPaymentRoundTripAndDeletedFilter() async throws {
        let p = Payment(id: UUID(), companyId: companyId, projectId: project.id, scheduleItemId: nil, amount: Money(7600, .cad), paidOn: CalendarDate(storage: "2026-09-14")!, method: .eTransfer, notes: "deposit", createdAt: now, updatedAt: now, deletedAt: nil)
        let gone = Payment(id: UUID(), companyId: companyId, projectId: project.id, scheduleItemId: nil, amount: Money(1, .cad), paidOn: CalendarDate(storage: "2026-09-14")!, method: .cash, notes: nil, createdAt: now, updatedAt: now, deletedAt: now)
        try await db.writer.write { db in try PaymentRecord(p).insert(db); try PaymentRecord(gone).insert(db) }
        let back = try await db.writer.read { db in try PaymentRecord.fetchLive(db, projectId: self.project.id.dbKey, currency: .cad) }
        XCTAssertEqual(back, [p])
    }
}
