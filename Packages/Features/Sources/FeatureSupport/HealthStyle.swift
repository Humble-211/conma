import SwiftUI
import Domain
import DesignSystem

public extension HealthStatus {
    /// Stable code used for the `health.status.<name>` catalog key.
    var name: String {
        switch self {
        case .onTrack: return "onTrack"
        case .atRisk: return "atRisk"
        case .delayed: return "delayed"
        case .paymentRisk: return "paymentRisk"
        case .overBudget: return "overBudget"
        }
    }

    var titleKey: LocalizedStringKey { LocalizedStringKey("health.status." + name) }

    var tone: DSTone {
        switch self {
        case .onTrack: return .success
        case .atRisk: return .warning
        case .delayed, .paymentRisk, .overBudget: return .danger
        }
    }
}

public extension CostGroup {
    var titleKey: LocalizedStringKey { LocalizedStringKey("costGroup." + rawValue) }
}

public extension HealthReason {
    /// Localized sentence with parameters (money formatted with the company currency).
    func text(currency: String, locale: Locale) -> Text {
        switch self {
        case .budgetExceeded(let group, let over):
            let amount = MoneyFormat.string(over.amount, currencyCode: currency, locale: locale)
            return Text("health.reason.budgetExceeded \(Text(group.titleKey)) \(amount)")
        case .paymentOverdue(let count):
            return Text("health.reason.paymentOverdue \(count)")
        case .pastCompletionDate(let daysLate):
            return Text("health.reason.pastCompletionDate \(daysLate)")
        case .budgetNearLimit(let group, let percent):
            let used = Self.percentString(percent, locale: locale)
            return Text("health.reason.budgetNearLimit \(Text(group.titleKey)) \(used)")
        case .deadlineApproaching(let daysLeft, let progress):
            return Text("health.reason.deadlineApproaching \(daysLeft) \(progress)")
        }
    }

    private static func percentString(_ percent: Percentage?, locale: Locale) -> String {
        guard let percent else { return "—" } // lint:allow-string
        return LocaleNumberParser.string(percent.points, locale: locale, fractionDigits: 1) + "%" // lint:allow-string
    }
}
