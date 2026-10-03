// Packages/Domain/Sources/Domain/Insights/ProjectInsights.swift
import Foundation

public struct PaymentItemInsight: Hashable, Sendable, Identifiable {
    public let item: PaymentScheduleItem
    public let paid: Money
    public let remaining: Money
    public let status: PaymentStatus
    public var id: UUID { item.id }
    public init(item: PaymentScheduleItem, paid: Money, remaining: Money, status: PaymentStatus) { self.item = item; self.paid = paid; self.remaining = remaining; self.status = status }
}

public struct TimelineInsight: Hashable, Sendable {
    public let startDate: CalendarDate?
    public let estimatedCompletionDate: CalendarDate?
    public let daysElapsed: Int?
    public let daysRemaining: Int?
    public let totalDays: Int?
    public let expectedProgress: Int?

    public init(startDate: CalendarDate?, estimatedCompletionDate: CalendarDate?, daysElapsed: Int?, daysRemaining: Int?, totalDays: Int?, expectedProgress: Int?) {
        self.startDate = startDate; self.estimatedCompletionDate = estimatedCompletionDate; self.daysElapsed = daysElapsed
        self.daysRemaining = daysRemaining; self.totalDays = totalDays; self.expectedProgress = expectedProgress
    }

    /// Spec §3.1: elapsed = max(0, start→today); remaining = today→completion (negative = late);
    /// expected = round(elapsed/total×100) clamped 0…100; total 0 → 100 when today ≥ completion else 0.
    public static func make(start: CalendarDate?, completion: CalendarDate?, today: CalendarDate) -> TimelineInsight {
        let elapsed = start.map { max(0, $0.daysUntil(today)) }
        let remaining = completion.map { today.daysUntil($0) }
        var total: Int?
        if let start, let completion { total = start.daysUntil(completion) }
        var expected: Int?
        if let total, let elapsed {
            if total <= 0 { expected = (remaining ?? 0) <= 0 ? 100 : 0 }
            else {
                let ratio = Decimal(elapsed) * 100 / Decimal(total)
                var rounded = Decimal(); var source = ratio
                NSDecimalRound(&rounded, &source, 0, .plain)
                expected = min(100, max(0, NSDecimalNumber(decimal: rounded).intValue))
            }
        }
        return TimelineInsight(startDate: start, estimatedCompletionDate: completion, daysElapsed: elapsed, daysRemaining: remaining, totalDays: total, expectedProgress: expected)
    }
}

public struct ProjectInsights: Hashable, Sendable {
    public let projectId: UUID
    public let financials: ProjectFinancials?
    public let budgetAlerts: [BudgetAlert]
    public let payments: [PaymentItemInsight]
    public let unallocatedCollected: Money
    public let progress: Int
    public let health: ProjectHealth?
    public let timeline: TimelineInsight
    public init(projectId: UUID, financials: ProjectFinancials?, budgetAlerts: [BudgetAlert], payments: [PaymentItemInsight], unallocatedCollected: Money, progress: Int, health: ProjectHealth?, timeline: TimelineInsight) {
        self.projectId = projectId; self.financials = financials; self.budgetAlerts = budgetAlerts; self.payments = payments
        self.unallocatedCollected = unallocatedCollected; self.progress = progress; self.health = health; self.timeline = timeline
    }
}

public struct ProjectInsightsInputs: Sendable {
    public struct Snapshot: Sendable, Equatable {
        public var project: Project
        public var estimateLines: [ProjectEstimateLine]
        public var scheduleItems: [PaymentScheduleItem]
        public var expenses: [Expense]
        public var labourEntries: [LabourEntry]
        public var payments: [Payment]
        public init(project: Project, estimateLines: [ProjectEstimateLine], scheduleItems: [PaymentScheduleItem], expenses: [Expense], labourEntries: [LabourEntry], payments: [Payment]) {
            self.project = project; self.estimateLines = estimateLines; self.scheduleItems = scheduleItems; self.expenses = expenses; self.labourEntries = labourEntries; self.payments = payments
        }
        public func with(today: CalendarDate) -> ProjectInsightsInputs {
            ProjectInsightsInputs(project: project, estimateLines: estimateLines, scheduleItems: scheduleItems, expenses: expenses, labourEntries: labourEntries, payments: payments, today: today)
        }
    }
    public var project: Project
    public var estimateLines: [ProjectEstimateLine]
    public var scheduleItems: [PaymentScheduleItem]
    public var expenses: [Expense]
    public var labourEntries: [LabourEntry]
    public var payments: [Payment]
    public var today: CalendarDate
    public init(project: Project, estimateLines: [ProjectEstimateLine], scheduleItems: [PaymentScheduleItem], expenses: [Expense], labourEntries: [LabourEntry], payments: [Payment], today: CalendarDate) {
        self.project = project; self.estimateLines = estimateLines; self.scheduleItems = scheduleItems; self.expenses = expenses; self.labourEntries = labourEntries; self.payments = payments; self.today = today
    }
    public var snapshot: Snapshot { Snapshot(project: project, estimateLines: estimateLines, scheduleItems: scheduleItems, expenses: expenses, labourEntries: labourEntries, payments: payments) }
}
