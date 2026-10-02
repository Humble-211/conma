public enum ProfitLabel: Sendable, Hashable { case actual, projectedAtCurrentSpending }

public struct ProjectFinancials: Sendable, Hashable {
    public let adjustedContract: Money
    /// Every CostGroup has a key (zero when nothing was spent).
    public let actualByGroup: [CostGroup: Money]
    /// Only groups that have at least one estimate line have a key.
    public let estimateByGroup: [CostGroup: Money]
    public let totalCost: Money
    public let estimatedCost: Money
    public let projectedProfit: Money
    public let spentSoFar: Money
    public let collected: Money
    public let outstandingBalance: Money
    public let cashPosition: Money
    public let actualProfit: Money
    public let projectedMargin: Percentage?
    public let actualMargin: Percentage?
    public let profitLabel: ProfitLabel
}
