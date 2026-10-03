// Packages/Domain/Sources/Domain/Insights/Dashboard.swift
import Foundation

public struct DashboardInputs: Sendable {
    public struct Snapshot: Sendable {
        public var company: Company
        public var projects: [Project]
        public var customers: [Customer]
        public var estimateLines: [ProjectEstimateLine]
        public var scheduleItems: [PaymentScheduleItem]
        public var expenses: [Expense]
        public var labourEntries: [LabourEntry]
        public var payments: [Payment]
        public init(company: Company, projects: [Project], customers: [Customer], estimateLines: [ProjectEstimateLine], scheduleItems: [PaymentScheduleItem], expenses: [Expense], labourEntries: [LabourEntry], payments: [Payment]) {
            self.company = company; self.projects = projects; self.customers = customers; self.estimateLines = estimateLines
            self.scheduleItems = scheduleItems; self.expenses = expenses; self.labourEntries = labourEntries; self.payments = payments
        }
        public func with(today: CalendarDate) -> DashboardInputs {
            DashboardInputs(company: company, projects: projects, customers: customers, estimateLines: estimateLines, scheduleItems: scheduleItems, expenses: expenses, labourEntries: labourEntries, payments: payments, today: today)
        }
    }
    public var company: Company
    public var projects: [Project]
    public var customers: [Customer]
    public var estimateLines: [ProjectEstimateLine]
    public var scheduleItems: [PaymentScheduleItem]
    public var expenses: [Expense]
    public var labourEntries: [LabourEntry]
    public var payments: [Payment]
    public var today: CalendarDate
    public init(company: Company, projects: [Project], customers: [Customer], estimateLines: [ProjectEstimateLine], scheduleItems: [PaymentScheduleItem], expenses: [Expense], labourEntries: [LabourEntry], payments: [Payment], today: CalendarDate) {
        self.company = company; self.projects = projects; self.customers = customers; self.estimateLines = estimateLines
        self.scheduleItems = scheduleItems; self.expenses = expenses; self.labourEntries = labourEntries; self.payments = payments; self.today = today
    }
}

public enum AttentionKind: Int, Comparable, Sendable, Hashable {
    case overBudget = 0, paymentRisk, paymentOverdue, delayed, dueToday, startsToday, atRisk
    public static func < (l: AttentionKind, r: AttentionKind) -> Bool { l.rawValue < r.rawValue }
}

public enum AttentionItem: Hashable, Sendable, Identifiable {
    case health(projectId: UUID, status: HealthStatus, reason: HealthReason)
    case paymentOverdue(projectId: UUID, itemId: UUID, label: String, remaining: Money, daysLate: Int)
    case paymentDueToday(projectId: UUID, itemId: UUID, label: String, remaining: Money)
    case startsToday(projectId: UUID)

    public var kind: AttentionKind {
        switch self {
        case .health(_, let status, _):
            switch status {
            case .overBudget: return .overBudget
            case .paymentRisk: return .paymentRisk
            case .delayed: return .delayed
            case .atRisk, .onTrack: return .atRisk
            }
        case .paymentOverdue: return .paymentOverdue
        case .paymentDueToday: return .dueToday
        case .startsToday: return .startsToday
        }
    }
    public var projectId: UUID {
        switch self {
        case .health(let id, _, _), .paymentOverdue(let id, _, _, _, _), .paymentDueToday(let id, _, _, _), .startsToday(let id): return id
        }
    }
    public var id: String {
        switch self {
        case .paymentOverdue(_, let item, _, _, _), .paymentDueToday(_, let item, _, _): return "\(kind.rawValue):\(projectId.uuidString):\(item.uuidString)"
        default: return "\(kind.rawValue):\(projectId.uuidString)"
        }
    }
    /// Sort weight after kind: larger money first.
    var amountWeight: Decimal {
        switch self {
        case .health(_, _, let reason):
            if case .budgetExceeded(_, let over) = reason { return over.amount }
            return 0
        case .paymentOverdue(_, _, _, let m, _), .paymentDueToday(_, _, _, let m): return m.amount
        case .startsToday: return 0
        }
    }
}

public struct CompanyTotals: Hashable, Sendable {
    public let currency: CurrencyCode
    public let activeJobs: Int
    public let outstanding: Money
    public let collected: Money
    public let spent: Money
    public let cashPosition: Money
    public let excludedCount: Int
    public init(currency: CurrencyCode, activeJobs: Int, outstanding: Money, collected: Money, spent: Money, cashPosition: Money, excludedCount: Int) {
        self.currency = currency; self.activeJobs = activeJobs; self.outstanding = outstanding; self.collected = collected; self.spent = spent; self.cashPosition = cashPosition; self.excludedCount = excludedCount
    }
}

public enum CardGroup: Int, Comparable, Sendable, Hashable, CaseIterable {
    case inWork = 0, preStart, workDone
    public static func < (l: CardGroup, r: CardGroup) -> Bool { l.rawValue < r.rawValue }
}

public struct ProjectCard: Hashable, Sendable, Identifiable {
    public let project: Project
    public let customerName: String
    public let insights: ProjectInsights
    public let group: CardGroup
    public var id: UUID { project.id }
    public init(project: Project, customerName: String, insights: ProjectInsights, group: CardGroup) { self.project = project; self.customerName = customerName; self.insights = insights; self.group = group }
}

public struct Dashboard: Hashable, Sendable {
    public let totals: CompanyTotals
    public let attention: [AttentionItem]
    public let cards: [ProjectCard]
    public init(totals: CompanyTotals, attention: [AttentionItem], cards: [ProjectCard]) { self.totals = totals; self.attention = attention; self.cards = cards }
}
