import Foundation

public enum HealthStatus: Int, Comparable, Sendable, Hashable {
    case onTrack = 0, atRisk, delayed, paymentRisk, overBudget
    public static func < (lhs: HealthStatus, rhs: HealthStatus) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum HealthReason: Hashable, Sendable {
    case budgetExceeded(CostGroup, overBy: Money)
    case paymentOverdue(count: Int)
    case pastCompletionDate(daysLate: Int)
    case budgetNearLimit(CostGroup, percentUsed: Percentage?)
    case deadlineApproaching(daysLeft: Int, progress: Int)
}

public struct ProjectHealth: Hashable, Sendable {
    public let status: HealthStatus
    public let reasons: [HealthReason]
    public init(status: HealthStatus, reasons: [HealthReason]) { self.status = status; self.reasons = reasons }
}

public struct HealthInputs: Sendable {
    public var status: ProjectStatus
    public var estimatedCompletionDate: CalendarDate?
    public var progress: Int
    public var budgetAlerts: [BudgetAlert]
    public var paymentStatuses: [PaymentStatus]
    public var today: CalendarDate

    public init(status: ProjectStatus, estimatedCompletionDate: CalendarDate?, progress: Int, budgetAlerts: [BudgetAlert], paymentStatuses: [PaymentStatus], today: CalendarDate) {
        self.status = status; self.estimatedCompletionDate = estimatedCompletionDate; self.progress = progress
        self.budgetAlerts = budgetAlerts; self.paymentStatuses = paymentStatuses; self.today = today
    }
}

public enum ProjectHealthEvaluator {
    /// Spec 5.4 health table. Returns nil for terminal projects.
    public static func evaluate(_ inputs: HealthInputs) -> ProjectHealth? {
        let phase = inputs.status.phase
        guard phase != .terminal else { return nil }

        let budgetPhases: Set<ProjectPhase> = [.inWork, .workDone]
        let paymentApplies = phase != .preStart || inputs.status == .awaitingDeposit

        var exceeded: [HealthReason] = []
        var nearLimit: [HealthReason] = []
        if budgetPhases.contains(phase) {
            for alert in inputs.budgetAlerts {
                switch alert.level {
                case .exceeded: exceeded.append(.budgetExceeded(alert.group, overBy: alert.overBy ?? alert.actual))
                case .nearLimit: nearLimit.append(.budgetNearLimit(alert.group, percentUsed: alert.percentUsed))
                }
            }
        }

        var payment: [HealthReason] = []
        if paymentApplies {
            let overdue = inputs.paymentStatuses.filter { $0 == .overdue }.count
            if overdue > 0 { payment.append(.paymentOverdue(count: overdue)) }
        }

        var delayed: [HealthReason] = []
        var approaching: [HealthReason] = []
        if phase == .inWork, let completion = inputs.estimatedCompletionDate {
            let daysLeft = inputs.today.daysUntil(completion)
            if daysLeft < 0 {
                delayed.append(.pastCompletionDate(daysLate: -daysLeft))
            } else if (0...7).contains(daysLeft), inputs.progress < 80 {
                approaching.append(.deadlineApproaching(daysLeft: daysLeft, progress: inputs.progress))
            }
        }

        let reasons = exceeded + payment + delayed + nearLimit + approaching
        let status: HealthStatus
        if !exceeded.isEmpty { status = .overBudget }
        else if !payment.isEmpty { status = .paymentRisk }
        else if !delayed.isEmpty { status = .delayed }
        else if !nearLimit.isEmpty || !approaching.isEmpty { status = .atRisk }
        else { status = .onTrack }
        return ProjectHealth(status: status, reasons: reasons)
    }
}
