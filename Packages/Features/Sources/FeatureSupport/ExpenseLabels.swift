import SwiftUI
import Domain

public extension ExpenseCategory {
    var titleKey: LocalizedStringKey { LocalizedStringKey("expenseCategory." + rawValue) }
    var systemImage: String {
        switch self {
        case .materials: return "shippingbox"
        case .labour: return "person.2"
        case .subcontractor: return "person.badge.key"
        case .equipmentRental: return "truck.box"
        case .toolPurchase: return "wrench.and.screwdriver"
        case .permit: return "checkmark.seal"
        case .inspection: return "magnifyingglass"
        case .delivery: return "shippingbox.and.arrow.backward"
        case .fuel: return "fuelpump"
        case .wasteDisposal: return "trash"
        case .parking: return "parkingsign"
        case .office: return "paperclip"
        case .other, .custom: return "tag"
        }
    }
}

public extension ExpenseCategoryChoice {
    /// Built-ins are localized; custom names are user data, shown verbatim.
    func title(customName: String?) -> Text {
        switch self {
        case .standard(let category): return Text(category.titleKey)
        case .custom:
            if let customName, !customName.isEmpty { return Text(verbatim: customName) }
            return Text("category.picker.custom.fallback")
        }
    }
    var systemImage: String {
        if case .standard(let category) = self { return category.systemImage }
        return "tag"
    }
}

public extension PaymentMethod {
    var titleKey: LocalizedStringKey { LocalizedStringKey("paymentMethod." + rawValue) }
}

public extension ExpenseDraftError {
    var name: String {
        switch self {
        case .projectMissing: return "projectMissing"
        case .amountMissing: return "amountMissing"
        case .amountNotPositive: return "amountNotPositive"
        case .categoryMissing: return "categoryMissing"
        case .taxNegative: return "taxNegative"
        case .taxPercentOutOfRange: return "taxPercentOutOfRange"
        }
    }
    var messageKey: LocalizedStringKey { LocalizedStringKey("expense.error." + name) }
}

public extension ExpenseTitle {
    var text: Text {
        switch self {
        case .vendor(let name): return Text(verbatim: name)
        case .category(let category): return Text(category.titleKey)
        case .customCategory(let name):
            if name.isEmpty { return Text("category.picker.custom.fallback") }
            return Text(verbatim: name)
        }
    }
}
