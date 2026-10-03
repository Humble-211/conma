// Packages/Domain/Sources/Domain/Insights/DashboardComposer.swift
import Foundation

public enum DashboardComposer {
    public static func compose(_ inputs: DashboardInputs) -> Dashboard {
        let currency = inputs.company.currencyCode
        let zero = Money.zero(currency)
        let names = Dictionary(inputs.customers.filter { !$0.isDeleted }.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let linesBy = Dictionary(grouping: inputs.estimateLines, by: \.projectId)
        let itemsBy = Dictionary(grouping: inputs.scheduleItems, by: \.projectId)
        let expensesBy = Dictionary(grouping: inputs.expenses, by: \.projectId)
        let labourBy = Dictionary(grouping: inputs.labourEntries, by: \.projectId)
        let paymentsBy = Dictionary(grouping: inputs.payments, by: \.projectId)

        var cards: [ProjectCard] = []
        var attention: [AttentionItem] = []
        var activeJobs = 0, excluded = 0
        var outstanding = zero, collected = zero, spent = zero

        for project in inputs.projects where !project.isDeleted {
            let phase = project.status.phase
            if phase == .terminal { continue }
            let insights = ProjectInsightsComposer.compose(ProjectInsightsInputs(
                project: project, estimateLines: linesBy[project.id] ?? [], scheduleItems: itemsBy[project.id] ?? [], expenses: expensesBy[project.id] ?? [],
                labourEntries: labourBy[project.id] ?? [], payments: paymentsBy[project.id] ?? [], today: inputs.today))
            if phase == .inWork { activeJobs += 1 }
            if let f = insights.financials, project.contractValue.currency == currency,
               let o = try? outstanding.adding(f.outstandingBalance), let c = try? collected.adding(f.collected), let s = try? spent.adding(f.spentSoFar) {
                outstanding = o; collected = c; spent = s
            } else { excluded += 1 }

            let group: CardGroup = phase == .inWork ? .inWork : (phase == .preStart ? .preStart : .workDone)
            cards.append(ProjectCard(project: project, customerName: names[project.customerId] ?? "", insights: insights, group: group))

            if let h = insights.health, h.status != .onTrack, let reason = h.reasons.first {
                attention.append(.health(projectId: project.id, status: h.status, reason: reason))
            }
            for p in insights.payments {
                switch p.status {
                case .overdue:
                    let late = p.item.dueDate.map { $0.daysUntil(inputs.today) } ?? 0
                    attention.append(.paymentOverdue(projectId: project.id, itemId: p.item.id, label: p.item.label, remaining: p.remaining, daysLate: late))
                case .dueToday:
                    attention.append(.paymentDueToday(projectId: project.id, itemId: p.item.id, label: p.item.label, remaining: p.remaining))
                default: break
                }
            }
            if project.startDate == inputs.today, phase == .preStart || project.status == .scheduled {
                attention.append(.startsToday(projectId: project.id))
            }
        }

        let nameOf: (UUID) -> String = { id in inputs.projects.first { $0.id == id }?.name ?? "" }
        attention.sort { a, b in
            if a.kind != b.kind { return a.kind < b.kind }
            if a.amountWeight != b.amountWeight { return a.amountWeight > b.amountWeight }
            return nameOf(a.projectId) < nameOf(b.projectId)
        }
        cards.sort { a, b in
            if a.group != b.group { return a.group < b.group }
            switch a.group {
            case .inWork:
                let ha = a.insights.health?.status ?? .onTrack, hb = b.insights.health?.status ?? .onTrack
                if ha != hb { return ha > hb }
                return a.project.updatedAt > b.project.updatedAt
            case .preStart:
                switch (a.project.startDate, b.project.startDate) {
                case let (x?, y?) where x != y: return x < y
                case (nil, _?): return false
                case (_?, nil): return true
                default: return a.project.updatedAt > b.project.updatedAt
                }
            case .workDone: return a.project.updatedAt > b.project.updatedAt
            }
        }
        let cash = (try? collected.subtracting(spent)) ?? zero
        let totals = CompanyTotals(currency: currency, activeJobs: activeJobs, outstanding: outstanding, collected: collected, spent: spent, cashPosition: cash, excludedCount: excluded)
        return Dashboard(totals: totals, attention: attention, cards: cards)
    }
}
