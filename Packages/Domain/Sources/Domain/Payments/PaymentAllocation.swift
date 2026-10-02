import Foundation

public enum PaymentAllocation {
    /// Payments explicitly allocated to the item. Unallocated payments never count here.
    public static func paidForItem(_ itemId: UUID, payments: [Payment], currency: CurrencyCode) throws -> Money {
        try Money.sum(payments.filter { !$0.isDeleted && $0.scheduleItemId == itemId }.map(\.amount), currency: currency)
    }

    /// Every live payment of the project, allocated or not.
    public static func collected(_ payments: [Payment], currency: CurrencyCode) throws -> Money {
        try Money.sum(payments.filter { !$0.isDeleted }.map(\.amount), currency: currency)
    }
}
