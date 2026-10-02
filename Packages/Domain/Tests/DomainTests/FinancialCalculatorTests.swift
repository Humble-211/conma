import XCTest
@testable import Domain

final class FinancialCalculatorTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let company = UUID(), projectId = UUID(), customer = UUID(), employee = UUID()
    let day = CalendarDate(storage: "2026-10-05")!

    private func project(contract: Decimal, status: ProjectStatus = .inProgress) -> Project {
        Project(id: projectId, companyId: company, customerId: customer, name: "Basement", jobType: .basementRenovation, customJobType: nil, status: status,
                address: Address(line: "1 Main", unit: nil, city: nil, region: nil, postalCode: nil), scopeDescription: nil, scopeFields: [],
                startDate: nil, estimatedCompletionDate: nil, workingDays: nil, hoursPerDay: nil, workersPerDay: nil,
                contractValue: Money(contract, .cad), manualProgress: nil, depositRequiredToStart: false, createdAt: now, updatedAt: now, deletedAt: nil)
    }
    private func expense(_ category: ExpenseCategory, _ amount: Decimal, tax: Decimal = 0, deleted: Bool = false, group: CostGroup? = nil) -> Expense {
        Expense(id: UUID(), companyId: company, projectId: projectId, category: category, customCategoryId: category == .custom ? UUID() : nil,
                costGroup: group ?? category.defaultCostGroup!, vendorName: nil, amount: Money(amount, .cad), tax: Money(tax, .cad), spentOn: day,
                paymentMethod: nil, notes: nil, receiptImages: [], createdAt: now, updatedAt: now, deletedAt: deleted ? now : nil)
    }
    private func labour(_ days: Decimal, rate: Decimal) -> LabourEntry {
        LabourEntry(id: UUID(), companyId: company, projectId: projectId, employeeId: employee, workDate: day, days: days, dailyRate: Money(rate, .cad), notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
    }
    private func payment(_ amount: Decimal, item: UUID? = nil) -> Payment {
        Payment(id: UUID(), companyId: company, projectId: projectId, scheduleItemId: item, amount: Money(amount, .cad), paidOn: day, method: .eTransfer, notes: nil, createdAt: now, updatedAt: now, deletedAt: nil)
    }
    private func estimate(_ group: CostGroup, _ amount: Decimal) -> ProjectEstimateLine {
        ProjectEstimateLine(id: UUID(), companyId: company, projectId: projectId, costGroup: group, label: "\(group)", amount: Money(amount, .cad), quantity: nil, unitRate: nil, sortOrder: 0, createdAt: now, updatedAt: now, deletedAt: nil)
    }

    func testSpecExample() throws {
        let inputs = FinancialInputs(project: project(contract: 30_000),
                                     estimateLines: [estimate(.material, 6_000), estimate(.labour, 8_000), estimate(.other, 4_000)],
                                     expenses: [expense(.materials, 6_000), expense(.delivery, 1_000)],
                                     labourEntries: [labour(30, rate: 250)],
                                     payments: [payment(5_000), payment(15_000)],
                                     approvedChangeOrders: Money.zero(.cad))
        let f = try FinancialCalculator.compute(inputs)
        XCTAssertEqual(f.totalCost.storageString, "14500.00")
        XCTAssertEqual(f.actualByGroup[.material]?.storageString, "6000.00")
        XCTAssertEqual(f.actualByGroup[.labour]?.storageString, "7500.00")
        XCTAssertEqual(f.actualByGroup[.other]?.storageString, "1000.00")
        XCTAssertEqual(f.actualByGroup[.permit]?.storageString, "0.00")
        XCTAssertEqual(f.estimatedCost.storageString, "18000.00")
        XCTAssertEqual(f.projectedProfit.storageString, "12000.00")
        XCTAssertEqual(f.projectedMargin?.points, 40)
        XCTAssertEqual(f.actualProfit.storageString, "15500.00")
        XCTAssertEqual(f.actualMargin?.points, Decimal(string: "51.7")!)
        XCTAssertEqual(f.collected.storageString, "20000.00")
        XCTAssertEqual(f.outstandingBalance.storageString, "10000.00")
        XCTAssertEqual(f.cashPosition.storageString, "5500.00")
        XCTAssertEqual(f.spentSoFar, f.totalCost)
        XCTAssertEqual(f.profitLabel, .projectedAtCurrentSpending)
    }

    func testExpenseCostIncludesTaxAndUsesSnapshotGroup() throws {
        let custom = expense(.custom, 100, tax: 13, group: .equipment)
        let f = try FinancialCalculator.compute(FinancialInputs(project: project(contract: 1_000), estimateLines: [], expenses: [custom], labourEntries: [], payments: [], approvedChangeOrders: .zero(.cad)))
        XCTAssertEqual(f.actualByGroup[.equipment]?.storageString, "113.00")
        XCTAssertEqual(f.totalCost.storageString, "113.00")
    }

    func testSoftDeletedRecordsAreIgnored() throws {
        let f = try FinancialCalculator.compute(FinancialInputs(project: project(contract: 1_000), estimateLines: [], expenses: [expense(.materials, 100, deleted: true)], labourEntries: [], payments: [], approvedChangeOrders: .zero(.cad)))
        XCTAssertEqual(f.totalCost.storageString, "0.00")
    }

    func testEstimateByGroupDistinguishesMissingFromZero() throws {
        let f = try FinancialCalculator.compute(FinancialInputs(project: project(contract: 1_000), estimateLines: [estimate(.material, 0)], expenses: [], labourEntries: [], payments: [], approvedChangeOrders: .zero(.cad)))
        XCTAssertEqual(f.estimateByGroup[.material]?.storageString, "0.00")
        XCTAssertNil(f.estimateByGroup[.labour])
    }

    func testMarginNilWhenContractZero() throws {
        let f = try FinancialCalculator.compute(FinancialInputs(project: project(contract: 0), estimateLines: [], expenses: [], labourEntries: [], payments: [], approvedChangeOrders: .zero(.cad)))
        XCTAssertNil(f.projectedMargin)
        XCTAssertNil(f.actualMargin)
    }

    func testUnallocatedPaymentsCountTowardCollected() throws {
        let f = try FinancialCalculator.compute(FinancialInputs(project: project(contract: 1_000), estimateLines: [], expenses: [], labourEntries: [], payments: [payment(100, item: UUID()), payment(50, item: nil)], approvedChangeOrders: .zero(.cad)))
        XCTAssertEqual(f.collected.storageString, "150.00")
    }

    func testChangeOrdersAdjustContract() throws {
        let f = try FinancialCalculator.compute(FinancialInputs(project: project(contract: 30_000), estimateLines: [], expenses: [], labourEntries: [], payments: [], approvedChangeOrders: Money(7_500, .cad)))
        XCTAssertEqual(f.adjustedContract.storageString, "37500.00")
        XCTAssertEqual(f.outstandingBalance.storageString, "37500.00")
    }

    func testProfitLabelByStatus() throws {
        for status in [ProjectStatus.completed, .awaitingFinalPayment, .closed] {
            let f = try FinancialCalculator.compute(FinancialInputs(project: project(contract: 1, status: status), estimateLines: [], expenses: [], labourEntries: [], payments: [], approvedChangeOrders: .zero(.cad)))
            XCTAssertEqual(f.profitLabel, .actual, "\(status)")
        }
        for status in [ProjectStatus.inProgress, .cancelled, .estimate] {
            let f = try FinancialCalculator.compute(FinancialInputs(project: project(contract: 1, status: status), estimateLines: [], expenses: [], labourEntries: [], payments: [], approvedChangeOrders: .zero(.cad)))
            XCTAssertEqual(f.profitLabel, .projectedAtCurrentSpending, "\(status)")
        }
    }

    func testCurrencyMismatchThrows() {
        var usd = payment(10); usd.amount = Money(10, .usd)
        XCTAssertThrowsError(try FinancialCalculator.compute(FinancialInputs(project: project(contract: 1), estimateLines: [], expenses: [], labourEntries: [], payments: [usd], approvedChangeOrders: .zero(.cad)))) {
            XCTAssertEqual($0 as? DomainError, .currencyMismatch)
        }
    }
}
