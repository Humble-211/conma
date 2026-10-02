import Foundation

public enum FinancialCalculator {
    public static func compute(_ inputs: FinancialInputs) throws -> ProjectFinancials {
        let currency = inputs.project.contractValue.currency
        let zero = Money.zero(currency)

        let expenses = inputs.expenses.filter { !$0.isDeleted }
        let labour = inputs.labourEntries.filter { !$0.isDeleted }
        let payments = inputs.payments.filter { !$0.isDeleted }
        let estimates = inputs.estimateLines.filter { !$0.isDeleted }

        var actualByGroup: [CostGroup: Money] = [:]
        for group in CostGroup.allCases { actualByGroup[group] = zero }
        for expense in expenses {
            actualByGroup[expense.costGroup] = try actualByGroup[expense.costGroup, default: zero].adding(expense.totalCost())
        }
        for entry in labour {
            actualByGroup[.labour] = try actualByGroup[.labour, default: zero].adding(entry.cost)
        }

        var estimateByGroup: [CostGroup: Money] = [:]
        for line in estimates {
            estimateByGroup[line.costGroup] = try estimateByGroup[line.costGroup, default: zero].adding(line.amount)
        }

        let totalCost = try Money.sum(CostGroup.allCases.map { actualByGroup[$0] ?? zero }, currency: currency)
        let estimatedCost = try Money.sum(estimates.map(\.amount), currency: currency)
        let adjustedContract = try inputs.project.contractValue.adding(inputs.approvedChangeOrders)
        let collected = try Money.sum(payments.map(\.amount), currency: currency)
        let projectedProfit = try adjustedContract.subtracting(estimatedCost)
        let actualProfit = try adjustedContract.subtracting(totalCost)

        let label: ProfitLabel = (inputs.project.status.phase == .workDone || inputs.project.status == .closed) ? .actual : .projectedAtCurrentSpending

        return ProjectFinancials(
            adjustedContract: adjustedContract,
            actualByGroup: actualByGroup,
            estimateByGroup: estimateByGroup,
            totalCost: totalCost,
            estimatedCost: estimatedCost,
            projectedProfit: projectedProfit,
            spentSoFar: totalCost,
            collected: collected,
            outstandingBalance: try adjustedContract.subtracting(collected),
            cashPosition: try collected.subtracting(totalCost),
            actualProfit: actualProfit,
            projectedMargin: Percentage.ratio(projectedProfit, over: adjustedContract),
            actualMargin: Percentage.ratio(actualProfit, over: adjustedContract),
            profitLabel: label
        )
    }
}
