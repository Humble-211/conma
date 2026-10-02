import XCTest
@testable import Domain

final class ValidationTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let company = UUID(), project = UUID(), customer = UUID(), employee = UUID()

    private func baseProject() -> Project {
        Project(id: project, companyId: company, customerId: customer, name: "123 Main St", jobType: .kitchen, customJobType: nil,
                status: .inProgress, address: Address(line: "123 Main St", unit: nil, city: "Toronto", region: "ON", postalCode: "M1M 1M1"),
                scopeDescription: nil, scopeFields: [], startDate: CalendarDate(storage: "2026-10-01"),
                estimatedCompletionDate: CalendarDate(storage: "2026-10-20"), workingDays: 10, hoursPerDay: nil, workersPerDay: 3,
                contractValue: Money(30_000, .cad), manualProgress: nil, depositRequiredToStart: true,
                createdAt: now, updatedAt: now, deletedAt: nil)
    }

    func testValidProjectPasses() throws {
        XCTAssertNoThrow(try baseProject().validate())
    }

    func testProjectRejectsCompletionBeforeStart() {
        var p = baseProject()
        p.estimatedCompletionDate = CalendarDate(storage: "2026-09-30")
        XCTAssertThrowsError(try p.validate()) { XCTAssertEqual($0 as? DomainError, .completionBeforeStart) }
    }

    func testProjectRejectsOtherWithoutCustomJobType() {
        var p = baseProject(); p.jobType = .other
        XCTAssertThrowsError(try p.validate()) { XCTAssertEqual($0 as? DomainError, .customJobTypeRequired) }
        p.customJobType = "Sauna"
        XCTAssertNoThrow(try p.validate())
    }

    func testProjectRejectsBadProgressNegativeContractEmptyName() {
        var p = baseProject(); p.manualProgress = 101
        XCTAssertThrowsError(try p.validate()) { XCTAssertEqual($0 as? DomainError, .invalidProgress) }
        p = baseProject(); p.contractValue = Money(-1, .cad)
        XCTAssertThrowsError(try p.validate()) { XCTAssertEqual($0 as? DomainError, .negativeAmount) }
        p = baseProject(); p.name = "   "
        XCTAssertThrowsError(try p.validate()) { XCTAssertEqual($0 as? DomainError, .emptyName) }
        p = baseProject(); p.scopeFields = [ProjectScopeField(id: UUID(), companyId: company, projectId: project, fieldKey: "", valueText: "x", sortOrder: 0, createdAt: now, updatedAt: now, deletedAt: nil)]
        XCTAssertThrowsError(try p.validate()) { XCTAssertEqual($0 as? DomainError, .emptyFieldKey) }
    }

    func testPaymentAmountMustBePositive() {
        let p = Payment(id: UUID(), companyId: company, projectId: project, scheduleItemId: nil, amount: Money(0, .cad),
                        paidOn: CalendarDate(storage: "2026-10-09")!, method: .cash, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        XCTAssertThrowsError(try p.validate()) { XCTAssertEqual($0 as? DomainError, .invalidPaymentAmount) }
    }

    func testLabourDaysMustBePositive() {
        let e = LabourEntry(id: UUID(), companyId: company, projectId: project, employeeId: employee, workDate: CalendarDate(storage: "2026-10-05")!,
                            days: 0, dailyRate: Money(250, .cad), notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        XCTAssertThrowsError(try e.validate()) { XCTAssertEqual($0 as? DomainError, .invalidLabourDays) }
        XCTAssertEqual(LabourEntry.cost(days: Decimal(string: "0.5")!, dailyRate: Money(Decimal(string: "250.01")!, .cad)).storageString, "125.01")
    }

    func testExpenseCostGroupResolution() throws {
        XCTAssertEqual(try Expense.resolveCostGroup(category: .toolPurchase, customCategory: nil), .equipment)
        let custom = CustomExpenseCategory(id: UUID(), companyId: company, name: "Scaffolding", costGroup: .equipment, createdAt: now, updatedAt: now, deletedAt: nil)
        XCTAssertEqual(try Expense.resolveCostGroup(category: .custom, customCategory: custom), .equipment)
        XCTAssertThrowsError(try Expense.resolveCostGroup(category: .custom, customCategory: nil)) { XCTAssertEqual($0 as? DomainError, .customCategoryRequired) }
    }

    func testExpenseValidateChecksSnapshotAgainstMapping() {
        var e = Expense(id: UUID(), companyId: company, projectId: project, category: .materials, customCategoryId: nil, costGroup: .material,
                        vendorName: "Home Depot", amount: Money(100, .cad), tax: Money(13, .cad), spentOn: CalendarDate(storage: "2026-10-05")!,
                        paymentMethod: .creditCard, notes: nil, receiptImages: [], createdAt: now, updatedAt: now, deletedAt: nil)
        XCTAssertNoThrow(try e.validate())
        XCTAssertEqual(try e.totalCost().storageString, "113.00")
        e.costGroup = .labour
        XCTAssertThrowsError(try e.validate()) { XCTAssertEqual($0 as? DomainError, .costGroupMismatch) }
        e.costGroup = .material; e.tax = Money(-1, .cad)
        XCTAssertThrowsError(try e.validate()) { XCTAssertEqual($0 as? DomainError, .negativeAmount) }
        e.tax = Money(0, .cad); e.category = .custom; e.customCategoryId = nil
        XCTAssertThrowsError(try e.validate()) { XCTAssertEqual($0 as? DomainError, .customCategoryRequired) }
    }

    func testIsDeleted() {
        var c = Customer(id: UUID(), companyId: company, name: "Ann", phone: nil, email: nil, preferredContact: nil, companyName: nil, secondaryContact: nil, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        XCTAssertFalse(c.isDeleted)
        c.deletedAt = now
        XCTAssertTrue(c.isDeleted)
    }
}
