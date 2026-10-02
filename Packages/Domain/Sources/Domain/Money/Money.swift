import Foundation

public struct Money: Hashable, Sendable, Codable {
    /// Always exactly 2 decimal places (see spec 5.1).
    public let amount: Decimal
    public let currency: CurrencyCode

    public init(_ raw: Decimal, _ currency: CurrencyCode) {
        self.amount = Money.rounded(raw)
        self.currency = currency
    }

    /// Parses the canonical storage form: optional "-", digits, ".", exactly two digits.
    public init?(storage: String, currency: CurrencyCode) {
        guard Money.isCanonical(storage), let value = Decimal(string: storage, locale: nil) else { return nil }
        self.amount = value
        self.currency = currency
    }

    public static func zero(_ currency: CurrencyCode) -> Money { Money(0, currency) }

    /// The single rounding point of the domain: half away from zero, `scale` decimals.
    public static func rounded(_ value: Decimal, scale: Int = 2) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }

    public var isNegative: Bool { amount < 0 }
    public var isZero: Bool { amount == 0 }

    public var storageString: String {
        let cents = NSDecimalNumber(decimal: amount * 100).int64Value
        let magnitude = cents.magnitude
        let whole = magnitude / 100
        let fraction = magnitude % 100
        let fractionText = fraction < 10 ? "0\(fraction)" : "\(fraction)"
        return "\(cents < 0 ? "-" : "")\(whole).\(fractionText)"
    }

    public func adding(_ other: Money) throws -> Money {
        try requireSameCurrency(other)
        return Money(amount + other.amount, currency)
    }

    public func subtracting(_ other: Money) throws -> Money {
        try requireSameCurrency(other)
        return Money(amount - other.amount, currency)
    }

    public func multiplied(by factor: Decimal) -> Money {
        Money(amount * factor, currency)
    }

    public static func sum(_ values: [Money], currency: CurrencyCode) throws -> Money {
        var total = Money.zero(currency)
        for value in values { total = try total.adding(value) }
        return total
    }

    private func requireSameCurrency(_ other: Money) throws {
        guard currency == other.currency else { throw DomainError.currencyMismatch }
    }

    private static func isCanonical(_ text: String) -> Bool {
        var chars = Substring(text)
        if chars.first == "-" { chars = chars.dropFirst() }
        let parts = chars.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].count == 2 else { return false }
        return parts.allSatisfy { $0.allSatisfy(\.isNumber) } && parts[0].allSatisfy(\.isASCII) && parts[1].allSatisfy(\.isASCII)
    }
}
