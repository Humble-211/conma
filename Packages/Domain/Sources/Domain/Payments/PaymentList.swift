import Foundation

public struct PaymentRow: Hashable, Sendable, Identifiable {
    public let payment: Payment
    /// Label of the linked LIVE schedule item (a `schedule.row.*` key or user text); nil = not linked.
    public let itemLabel: String?
    public var id: UUID { payment.id }
    public init(payment: Payment, itemLabel: String?) { self.payment = payment; self.itemLabel = itemLabel }
}

public struct ProjectPaymentList: Hashable, Sendable {
    public let rows: [PaymentRow]
    public let collected: Money
    public let unallocated: Money
    public init(rows: [PaymentRow], collected: Money, unallocated: Money) { self.rows = rows; self.collected = collected; self.unallocated = unallocated }
}

public enum ProjectPaymentListComposer {
    /// Project detail's Payments card: live payments newest first (paid date, then creation); a payment whose stage was deleted
    /// counts as not linked, exactly like `ProjectInsightsComposer`.
    public static func compose(payments: [Payment], scheduleItems: [PaymentScheduleItem], currency: CurrencyCode) -> ProjectPaymentList {
        let zero = Money.zero(currency)
        let labels = Dictionary(scheduleItems.filter { !$0.isDeleted }.map { ($0.id, $0.label) }, uniquingKeysWith: { a, _ in a })
        let live = payments.filter { !$0.isDeleted }
        let rows = live
            .sorted { ($0.paidOn, $0.createdAt, $0.id.uuidString) > ($1.paidOn, $1.createdAt, $1.id.uuidString) }
            .map { PaymentRow(payment: $0, itemLabel: $0.scheduleItemId.flatMap { labels[$0] }) }
        let collected = (try? Money.sum(live.map(\.amount), currency: currency)) ?? zero
        let unallocated = (try? Money.sum(rows.filter { $0.itemLabel == nil }.map(\.payment.amount), currency: currency)) ?? zero
        return ProjectPaymentList(rows: rows, collected: collected, unallocated: unallocated)
    }
}
