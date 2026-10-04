import SwiftUI
import Domain
import DesignSystem

public extension ActivityAction {
    var systemImage: String {
        switch self {
        case .projectCreated: return "plus.circle"
        case .projectDeleted: return "trash"
        case .contractValueChanged: return "dollarsign.circle"
        case .progressChanged: return "chart.line.uptrend.xyaxis"
        case .statusChanged: return "arrow.triangle.2.circlepath"
        case .expenseAdded: return "cart"
        case .paymentReceived: return "banknote"
        case .estimateChanged: return "list.number"
        case .scheduleChanged: return "calendar.badge.clock"
        case .customerCreated, .customerChanged: return "person"
        case .scopeChanged: return "doc.text"
        case .timelineChanged: return "calendar"
        case .expenseUpdated: return "cart.badge.plus"
        case .expenseDeleted: return "cart.badge.minus"
        case .paymentUpdated: return "banknote"
        case .paymentDeleted: return "minus.circle"
        case .labourLogged, .labourUpdated: return "person.badge.clock"
        case .labourDeleted: return "person.badge.minus"
        }
    }

    /// Parameterless sentence (`activity.<raw>`), also the fallback when details cannot be read.
    var titleKey: LocalizedStringKey { LocalizedStringKey("activity." + rawValue) }
}

public extension ActivityDetail {
    func text(currency: String, locale: Locale) -> Text {
        func money(_ stored: String) -> String {
            MoneyFormat.string(Decimal(string: stored, locale: Locale(identifier: "en_US_POSIX")) ?? 0, currencyCode: currency, locale: locale) // lint:allow-string
        }
        func percent(_ value: Int?) -> String { value.map { "\($0)%" } ?? "—" } // lint:allow-string
        switch self {
        case .statusChanged(let from, let to):
            return Text("activity.statusChanged \(Text(from.titleKey)) \(Text(to.titleKey))")
        case .progressChanged(let from, let to):
            let fromText = percent(from), toText = percent(to)
            return Text("activity.progressChanged \(fromText) \(toText)")
        case .contractValueChanged(let from, let to):
            let fromText = money(from), toText = money(to)
            return Text("activity.contractValueChanged \(fromText) \(toText)")
        case .estimateChanged(let group, let from, let to):
            let groupText = group.map { Text($0.titleKey) } ?? Text("activity.estimate.all")
            let fromText = money(from), toText = money(to)
            return Text("activity.estimateChanged \(groupText) \(fromText) \(toText)")
        case .scheduleChanged(let from, let to):
            let fromText = money(from), toText = money(to)
            return Text("activity.scheduleChanged \(fromText) \(toText)")
        case .customerChanged(let fromName, let toName):
            return Text("activity.customerChanged \(fromName) \(toName)")
        case .expense(let action, let title, let total, let previous):
            // A custom category whose name could not be read has an empty title: use the plain sentence.
            if case .customCategory(let name) = title, name.isEmpty { return Text(action.titleKey) }
            let titleText = title.text
            let totalText = money(total)
            switch action {
            case .expenseUpdated:
                let fromText = money(previous ?? total)
                return Text("activity.expenseUpdated \(titleText) \(fromText) \(totalText)")
            case .expenseDeleted:
                return Text("activity.expenseDeleted \(titleText) \(totalText)")
            default:
                return Text("activity.expenseAdded \(titleText) \(totalText)")
            }
        case .payment(let action, let title, let amount, let previous):
            let titleText = title.text
            let amountText = money(amount)
            switch action {
            case .paymentUpdated:
                // No "from": the amount did not change (stage, method, date or notes did).
                guard let previous else { return Text("activity.paymentEdited \(amountText) \(titleText)") }
                let fromText = money(previous)
                return Text("activity.paymentUpdated \(titleText) \(fromText) \(amountText)")
            case .paymentDeleted:
                return Text("activity.paymentDeleted \(amountText) \(titleText)")
            default:
                return Text("activity.paymentReceived \(amountText) \(titleText)")
            }
        case .labour(let action, let names, let total, let previous):
            let totalText = money(total)
            switch action {
            case .labourUpdated:
                // No "from": the cost did not change (date or notes did).
                guard let previous else { return Text("activity.labourEdited \(names) \(totalText)") }
                let fromText = money(previous)
                return Text("activity.labourUpdated \(names) \(fromText) \(totalText)")
            case .labourDeleted:
                return Text("activity.labourDeleted \(names) \(totalText)")
            default:
                return Text("activity.labourLogged \(names) \(totalText)")
            }
        case .plain(let action):
            return Text(action.titleKey)
        }
    }
}

public extension ActivityLogEntry {
    /// The localized sentence; amounts use the currency written with the row (3b money rows), else `fallbackCurrency`.
    func sentence(fallbackCurrency: CurrencyCode, locale: Locale) -> Text {
        let currency = ActivityDescription.currency(for: self) ?? fallbackCurrency
        return ActivityDescription.detail(for: self).text(currency: currency.rawValue, locale: locale)
    }
}
