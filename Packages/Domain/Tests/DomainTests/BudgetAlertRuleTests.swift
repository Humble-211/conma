import XCTest
@testable import Domain

final class BudgetAlertRuleTests: XCTestCase {
    private func financials(estimate: [CostGroup: Decimal], actual: [CostGroup: Decimal]) -> ProjectFinancials {
        let zero = Money.zero(.cad)
        var actualMap: [CostGroup: Money] = [:]
        for g in CostGroup.allCases { actualMap[g] = Money(actual[g] ?? 0, .cad) }
        let estimateMap = estimate.mapValues { Money($0, .cad) }
        return ProjectFinancials(adjustedContract: zero, actualByGroup: actualMap, estimateByGroup: estimateMap, totalCost: zero, estimatedCost: zero,
                                 projectedProfit: zero, spentSoFar: zero, collected: zero, outstandingBalance: zero, cashPosition: zero, actualProfit: zero,
                                 projectedMargin: nil, actualMargin: nil, profitLabel: .projectedAtCurrentSpending)
    }

    func testThresholds() throws {
        XCTAssertEqual(try BudgetAlertRule.alerts(for: financials(estimate: [.material: 10_000], actual: [.material: 8_900])), [])
        let near = try BudgetAlertRule.alerts(for: financials(estimate: [.material: 10_000], actual: [.material: 9_000]))
        XCTAssertEqual(near.count, 1)
        XCTAssertEqual(near[0].level, .nearLimit)
        XCTAssertEqual(near[0].percentUsed?.points, 90)
        XCTAssertNil(near[0].overBy)
        let full = try BudgetAlertRule.alerts(for: financials(estimate: [.material: 10_000], actual: [.material: 10_000]))
        XCTAssertEqual(full[0].level, .nearLimit)
        XCTAssertEqual(full[0].percentUsed?.points, 100)
        let over = try BudgetAlertRule.alerts(for: financials(estimate: [.material: 10_000], actual: [.material: 10_100]))
        XCTAssertEqual(over[0].level, .exceeded)
        XCTAssertEqual(over[0].overBy?.storageString, "100.00")
        XCTAssertEqual(over[0].percentUsed?.points, 101)
    }

    func testNoEstimateNoAlert() throws {
        XCTAssertEqual(try BudgetAlertRule.alerts(for: financials(estimate: [:], actual: [.material: 50_000])), [])
    }

    func testZeroActualNoAlert() throws {
        XCTAssertEqual(try BudgetAlertRule.alerts(for: financials(estimate: [.material: 0], actual: [:])), [])
        XCTAssertEqual(try BudgetAlertRule.alerts(for: financials(estimate: [.material: 100], actual: [:])), [])
    }

    func testZeroEstimateWithSpendIsExceeded() throws {
        let alerts = try BudgetAlertRule.alerts(for: financials(estimate: [.material: 0], actual: [.material: 250]))
        XCTAssertEqual(alerts[0].level, .exceeded)
        XCTAssertEqual(alerts[0].overBy?.storageString, "250.00")
        XCTAssertNil(alerts[0].percentUsed)
    }

    func testBoundaryUsesExactDecimalComparison() throws {
        // 89.995 % would round to 90.0 but is below the threshold.
        let alerts = try BudgetAlertRule.alerts(for: financials(estimate: [.material: 100_000], actual: [.material: Decimal(string: "89995")!]))
        XCTAssertEqual(alerts, [])
    }

    func testOrderFollowsCostGroupCases() throws {
        let alerts = try BudgetAlertRule.alerts(for: financials(estimate: [.other: 10, .material: 10], actual: [.other: 20, .material: 20]))
        XCTAssertEqual(alerts.map(\.group), [.material, .other])
    }
}
