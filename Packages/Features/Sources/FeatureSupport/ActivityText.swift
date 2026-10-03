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
        case .plain(let action):
            return Text(action.titleKey)
        }
    }
}
