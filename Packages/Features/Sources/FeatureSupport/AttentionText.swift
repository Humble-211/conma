import SwiftUI
import Domain
import DesignSystem

public extension AttentionItem {
    var tone: DSTone {
        switch kind {
        case .overBudget, .paymentOverdue, .paymentRisk: return .danger
        case .delayed, .dueToday: return .caution
        case .startsToday: return .info
        case .atRisk: return .warning
        }
    }

    var systemImage: String {
        switch kind {
        case .overBudget: return "chart.bar.xaxis"
        case .paymentOverdue, .paymentRisk, .dueToday: return "dollarsign.circle"
        case .delayed: return "clock.badge.exclamationmark"
        case .startsToday: return "flag"
        case .atRisk: return "exclamationmark.triangle"
        }
    }

    /// One-line description; the project name is shown separately by the row.
    func text(currency: String, locale: Locale) -> Text {
        switch self {
        case .health(_, _, let reason):
            return reason.text(currency: currency, locale: locale)
        case .paymentOverdue(_, _, let label, let remaining, let days):
            let amount = MoneyFormat.string(remaining.amount, currencyCode: currency, locale: locale)
            return Text("attention.paymentOverdue \(RowLabel.text(label)) \(days) \(amount)")
        case .paymentDueToday(_, _, let label, let remaining):
            let amount = MoneyFormat.string(remaining.amount, currencyCode: currency, locale: locale)
            return Text("attention.paymentDueToday \(RowLabel.text(label)) \(amount)")
        case .startsToday:
            return Text("attention.startsToday")
        }
    }
}
