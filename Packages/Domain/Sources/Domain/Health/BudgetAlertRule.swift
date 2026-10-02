import Foundation

public enum BudgetAlertLevel: Sendable, Hashable { case nearLimit, exceeded }

public struct BudgetAlert: Hashable, Sendable {
    public let group: CostGroup
    public let level: BudgetAlertLevel
    public let estimate: Money
    public let actual: Money
    public let overBy: Money?
    public let percentUsed: Percentage?
}

public enum BudgetAlertRule {
    /// Spec 5.4 table. Compares with exact Decimal arithmetic, never with rounded percentages.
    public static func alerts(for financials: ProjectFinancials) throws -> [BudgetAlert] {
        var result: [BudgetAlert] = []
        for group in CostGroup.allCases {
            guard let estimate = financials.estimateByGroup[group] else { continue }
            guard let actual = financials.actualByGroup[group], !actual.isZero else { continue }
            if estimate.isZero {
                result.append(BudgetAlert(group: group, level: .exceeded, estimate: estimate, actual: actual, overBy: actual, percentUsed: nil))
                continue
            }
            let percentUsed = Percentage.ratio(actual, over: estimate)
            if actual.amount > estimate.amount {
                result.append(BudgetAlert(group: group, level: .exceeded, estimate: estimate, actual: actual, overBy: try actual.subtracting(estimate), percentUsed: percentUsed))
            } else if actual.amount * 100 >= estimate.amount * 90 {
                result.append(BudgetAlert(group: group, level: .nearLimit, estimate: estimate, actual: actual, overBy: nil, percentUsed: percentUsed))
            }
        }
        return result
    }
}
