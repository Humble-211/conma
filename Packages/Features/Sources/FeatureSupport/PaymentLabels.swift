import SwiftUI
import Domain
import DesignSystem

public extension PaymentStatus {
    var titleKey: LocalizedStringKey { LocalizedStringKey("payment.status." + rawValue) }
    var tone: DSTone {
        switch self {
        case .paid: return .success
        case .overdue: return .danger
        case .dueToday, .dueSoon, .partiallyPaid: return .warning
        case .upcoming: return .neutral
        }
    }
}

public extension PaymentDraftError {
    var name: String {
        switch self {
        case .amountMissing: return "amountMissing"
        case .amountNotPositive: return "amountNotPositive"
        }
    }
    var messageKey: LocalizedStringKey { LocalizedStringKey("payment.error." + name) }
}

public extension LabourDraftError {
    var name: String {
        switch self {
        case .noCrewSelected: return "noCrewSelected"
        case .daysMissing: return "daysMissing"
        case .daysNotPositive: return "daysNotPositive"
        case .rateMissing: return "rateMissing"
        case .rateNegative: return "rateNegative"
        }
    }
    var messageKey: LocalizedStringKey { LocalizedStringKey("labour.error." + name) }
}

public extension EmployeeDraftError {
    var name: String {
        switch self {
        case .nameMissing: return "nameMissing"
        case .rateNegative: return "rateNegative"
        }
    }
    var messageKey: LocalizedStringKey { LocalizedStringKey("crew.error." + name) }
}

public extension PaymentTitle {
    /// Stage label (catalog key or user text) or the payment method.
    var text: Text {
        switch self {
        case .item(let label): return RowLabel.text(label)
        case .method(let method): return Text(method.titleKey)
        }
    }
}

public enum LabourDays {
    /// "1 day" / "0.5 days" / "8 days", the number in the app locale.
    public static func text(_ days: Decimal, locale: Locale) -> Text {
        if days == 1 { return Text("labour.days.one") }
        let number = LocaleNumberParser.string(days, locale: locale, fractionDigits: 2)
        return Text("labour.days.count \(number)")
    }
}
