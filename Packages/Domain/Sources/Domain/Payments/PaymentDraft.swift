import Foundation

public enum PaymentDraftError: Hashable, Sendable, CaseIterable {
    case amountMissing, amountNotPositive
}

/// The payment form's state (spec §3.1). Pure: no `Date()`, no persistence. The project is fixed by the entry point.
public struct PaymentDraft: Hashable, Sendable {
    /// Chip order: e-Transfer first (the common Canadian method), then cheque and cash.
    public static let methodOrder: [PaymentMethod] = [.eTransfer, .cheque, .cash, .bankTransfer, .creditCard, .other]

    /// Method of the company's most recently created live payment, else e-Transfer (spec §2 "Cách trả mặc định").
    public static func defaultMethod(lastUsed: PaymentMethod?) -> PaymentMethod { lastUsed ?? .eTransfer }

    public var amount: Decimal?
    public var paidOn: CalendarDate
    public var method: PaymentMethod
    public var scheduleItemId: UUID?
    public var notes: String

    public init(paidOn: CalendarDate, method: PaymentMethod, scheduleItemId: UUID? = nil, amount: Decimal? = nil) {
        self.amount = amount; self.paidOn = paidOn; self.method = method; self.scheduleItemId = scheduleItemId; self.notes = ""
    }

    public init(editing payment: Payment) {
        amount = payment.amount.amount
        paidOn = payment.paidOn
        method = payment.method
        scheduleItemId = payment.scheduleItemId
        notes = payment.notes ?? ""
    }

    public var errors: [PaymentDraftError] {
        guard let amount else { return [.amountMissing] }
        return Money.rounded(amount) <= 0 ? [.amountNotPositive] : []
    }

    public var canSave: Bool { errors.isEmpty }

    public func makePayment(id: UUID, companyId: UUID, projectId: UUID, currency: CurrencyCode, now: Date) throws -> Payment {
        let money = try resolvedAmount(currency: currency)
        return Payment(id: id, companyId: companyId, projectId: projectId, scheduleItemId: scheduleItemId, amount: money, paidOn: paidOn,
                       method: method, notes: Self.clean(notes), createdAt: now, updatedAt: now, deletedAt: nil)
    }

    /// Edit: keeps identity, project and creation time.
    public func apply(to existing: Payment, now: Date) throws -> Payment {
        let money = try resolvedAmount(currency: existing.amount.currency)
        return Payment(id: existing.id, companyId: existing.companyId, projectId: existing.projectId, scheduleItemId: scheduleItemId, amount: money,
                       paidOn: paidOn, method: method, notes: Self.clean(notes), createdAt: existing.createdAt, updatedAt: now, deletedAt: existing.deletedAt)
    }

    /// The single rounding point of a typed amount.
    private func resolvedAmount(currency: CurrencyCode) throws -> Money {
        guard errors.isEmpty, let amount else { throw DomainError.incompletePayment }
        return Money(amount, currency)
    }

    static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
