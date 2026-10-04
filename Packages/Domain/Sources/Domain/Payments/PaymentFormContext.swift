import Foundation

/// A schedule item as the payment form shows it: paid by OTHER payments, what is left, its status.
public struct PaymentItemOption: Hashable, Sendable, Identifiable {
    public let item: PaymentScheduleItem
    public let paid: Money
    public let remaining: Money
    public let status: PaymentStatus
    public var id: UUID { item.id }
    public init(item: PaymentScheduleItem, paid: Money, remaining: Money, status: PaymentStatus) {
        self.item = item; self.paid = paid; self.remaining = remaining; self.status = status
    }
}

/// One-tap amounts (spec §2 "Chip số tiền").
public enum PaymentSuggestion: Hashable, Sendable {
    case remaining(Money)
    case fullItem(Money)
    case outstanding(Money)

    public var money: Money {
        switch self {
        case .remaining(let m), .fullItem(let m), .outstanding(let m): return m
        }
    }
}

public enum PaymentFormContext {
    /// Live items by sort order; `paid` counts live payments except `excluding` (the payment being edited).
    public static func options(items: [PaymentScheduleItem], payments: [Payment], excluding paymentId: UUID?, today: CalendarDate, currency: CurrencyCode) -> [PaymentItemOption] {
        let zero = Money.zero(currency)
        let counted = payments.filter { !$0.isDeleted && $0.id != paymentId }
        return items.filter { !$0.isDeleted }.sorted { $0.sortOrder < $1.sortOrder }.map { item in
            let paid = (try? PaymentAllocation.paidForItem(item.id, payments: counted, currency: currency)) ?? zero
            let left = (try? item.amount.subtracting(paid)) ?? zero
            return PaymentItemOption(item: item, paid: paid, remaining: left.isNegative ? zero : left,
                                     status: PaymentStatusResolver.status(item: item, paidForItem: paid, today: today))
        }
    }

    /// "Record payment" without a stage: the first stage (in order) that is not fully paid.
    public static func defaultItemId(_ options: [PaymentItemOption]) -> UUID? {
        options.first { $0.status != .paid }?.id
    }

    /// Contract − collected, ignoring `excluding`; nil on a currency mismatch.
    public static func outstanding(project: Project, payments: [Payment], excluding paymentId: UUID?) -> Money? {
        let currency = project.contractValue.currency
        guard let collected = try? PaymentAllocation.collected(payments.filter { $0.id != paymentId }, currency: currency) else { return nil }
        return try? project.contractValue.subtracting(collected)
    }

    public static func suggestions(option: PaymentItemOption?, outstanding: Money?) -> [PaymentSuggestion] {
        guard let option else {
            if let outstanding, outstanding.amount > 0 { return [.outstanding(outstanding)] }
            return []
        }
        guard option.remaining.amount > 0 else { return [] }
        var result: [PaymentSuggestion] = [.remaining(option.remaining)]
        if option.paid.amount > 0 { result.append(.fullItem(option.item.amount)) }
        return result
    }

    /// How much the typed amount exceeds what is left on the stage (accepted, shown as a notice).
    public static func overpayment(amount: Decimal?, option: PaymentItemOption?) -> Money? {
        guard let amount, let option else { return nil }
        guard let extra = try? Money(amount, option.remaining.currency).subtracting(option.remaining), extra.amount > 0 else { return nil }
        return extra
    }
}
