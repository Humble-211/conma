// Packages/Domain/Sources/Domain/Insights/ProjectInsightsComposer.swift
import Foundation

public enum ProjectInsightsComposer {
    public static func compose(_ inputs: ProjectInsightsInputs) -> ProjectInsights {
        let project = inputs.project
        let currency = project.contractValue.currency
        let zero = Money.zero(currency)
        let items = inputs.scheduleItems.filter { !$0.isDeleted }.sorted { $0.sortOrder < $1.sortOrder }
        let payments = inputs.payments.filter { !$0.isDeleted }

        let financials = try? FinancialCalculator.compute(FinancialInputs(project: project, estimateLines: inputs.estimateLines, expenses: inputs.expenses,
                                                                           labourEntries: inputs.labourEntries, payments: payments, approvedChangeOrders: zero))
        let alerts = financials.flatMap { try? BudgetAlertRule.alerts(for: $0) } ?? []

        let liveIds = Set(items.map(\.id))
        var paidByItem: [UUID: Money] = [:]
        var unallocated = zero
        for p in payments {
            if let id = p.scheduleItemId, liveIds.contains(id), let sum = try? (paidByItem[id] ?? zero).adding(p.amount) { paidByItem[id] = sum }
            else if let sum = try? unallocated.adding(p.amount) { unallocated = sum }
        }
        let paymentInsights = items.map { item -> PaymentItemInsight in
            let paid = paidByItem[item.id] ?? zero
            let remaining = (try? item.amount.subtracting(paid)).map { $0.isNegative ? zero : $0 } ?? zero
            return PaymentItemInsight(item: item, paid: paid, remaining: remaining, status: PaymentStatusResolver.status(item: item, paidForItem: paid, today: inputs.today))
        }

        let progress = ProgressCalculator.percent(tasks: [], manualProgress: project.manualProgress)
        let health = ProjectHealthEvaluator.evaluate(HealthInputs(status: project.status, estimatedCompletionDate: project.estimatedCompletionDate, progress: progress,
                                                                  budgetAlerts: alerts, paymentStatuses: paymentInsights.map(\.status), today: inputs.today))
        let timeline = TimelineInsight.make(start: project.startDate, completion: project.estimatedCompletionDate, today: inputs.today)
        return ProjectInsights(projectId: project.id, financials: financials, budgetAlerts: alerts, payments: paymentInsights,
                               unallocatedCollected: unallocated, progress: progress, health: health, timeline: timeline)
    }
}
