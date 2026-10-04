import Foundation

/// How an expense is named in a sentence: vendor when known, else its category.
public enum ExpenseTitle: Hashable, Sendable {
    case vendor(String)
    case category(ExpenseCategory)
    case customCategory(String)
}

/// How a payment is named in a sentence: its schedule stage when linked, else its method.
public enum PaymentTitle: Hashable, Sendable {
    case item(String)            // a `schedule.row.*` key or user text
    case method(PaymentMethod)
}

public enum ActivityDetail: Hashable, Sendable {
    case statusChanged(from: ProjectStatus, to: ProjectStatus)
    case progressChanged(from: Int?, to: Int?)
    case contractValueChanged(from: String, to: String)
    case estimateChanged(group: CostGroup?, from: String, to: String)
    case scheduleChanged(from: String, to: String)
    case customerChanged(fromName: String, toName: String)
    case expense(action: ActivityAction, title: ExpenseTitle, total: String, previousTotal: String?)
    case payment(action: ActivityAction, title: PaymentTitle, amount: String, previousAmount: String?)
    case labour(action: ActivityAction, names: String, total: String, previousTotal: String?)
    case plain(ActivityAction)
}

public enum ActivityDescription {
    public static func detail(for entry: ActivityLogEntry) -> ActivityDetail {
        guard let data = entry.detailsJSON.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .plain(entry.action) }
        func s(_ k: String) -> String? { obj[k] as? String }
        switch entry.action {
        case .statusChanged:
            guard let f = s("from").flatMap(ProjectStatus.init(rawValue:)), let t = s("to").flatMap(ProjectStatus.init(rawValue:)) else { return .plain(entry.action) }
            return .statusChanged(from: f, to: t)
        case .progressChanged:
            guard let f = s("from"), let t = s("to") else { return .plain(entry.action) }
            return .progressChanged(from: f.isEmpty ? nil : Int(f), to: t.isEmpty ? nil : Int(t))
        case .contractValueChanged:
            guard let f = s("from"), let t = s("to") else { return .plain(entry.action) }
            return .contractValueChanged(from: f, to: t)
        case .estimateChanged:
            guard let f = s("from"), let t = s("to") else { return .plain(entry.action) }
            return .estimateChanged(group: s("group").flatMap(CostGroup.init(rawValue:)), from: f, to: t)
        case .scheduleChanged:
            guard let f = s("from"), let t = s("to") else { return .plain(entry.action) }
            return .scheduleChanged(from: f, to: t)
        case .customerChanged:
            guard let f = s("from"), let t = s("to") else { return .plain(entry.action) }
            return .customerChanged(fromName: f, toName: t)
        case .expenseAdded, .expenseUpdated, .expenseDeleted:
            guard let total = s("total"), let category = s("category").flatMap(ExpenseCategory.init(rawValue:)) else { return .plain(entry.action) }
            let title: ExpenseTitle
            if let vendor = s("vendor"), !vendor.isEmpty { title = .vendor(vendor) }
            else if category == .custom { title = .customCategory(s("categoryName") ?? "") }
            else { title = .category(category) }
            return .expense(action: entry.action, title: title, total: total, previousTotal: entry.action == .expenseUpdated ? s("from") : nil)
        case .paymentReceived, .paymentUpdated, .paymentDeleted:
            guard let amount = s("amount"), let method = s("method").flatMap(PaymentMethod.init(rawValue:)) else { return .plain(entry.action) }
            let item = s("item") ?? ""
            return .payment(action: entry.action, title: item.isEmpty ? .method(method) : .item(item), amount: amount,
                            previousAmount: entry.action == .paymentUpdated ? s("from") : nil)
        case .labourLogged, .labourUpdated, .labourDeleted:
            guard let total = s("total"), let names = s("names"), !names.isEmpty else { return .plain(entry.action) }
            return .labour(action: entry.action, names: names, total: total, previousTotal: entry.action == .labourUpdated ? s("from") : nil)
        default: return .plain(entry.action)
        }
    }

    /// The currency written with the row (3b money rows); nil for older rows, which fall back to the company currency.
    public static func currency(for entry: ActivityLogEntry) -> CurrencyCode? {
        guard let data = entry.detailsJSON.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return (obj["currency"] as? String).flatMap(CurrencyCode.init(rawValue:))
    }
}
