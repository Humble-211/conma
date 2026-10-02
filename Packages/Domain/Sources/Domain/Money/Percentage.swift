import Foundation

/// Percentage points: `Percentage(points: 10)` means 10 %, never "10 times".
public struct Percentage: Hashable, Sendable, Codable {
    public let points: Decimal

    private init(points: Decimal) { self.points = points }

    /// User input: 0...100 with at most two decimals.
    public static func input(_ points: Decimal) throws -> Percentage {
        guard points >= 0, points <= 100, Money.rounded(points, scale: 2) == points else {
            throw DomainError.invalidPercentage
        }
        return Percentage(points: points)
    }

    /// Computed result (margin, budget used): unbounded, rounded to one decimal.
    public static func computed(_ points: Decimal) -> Percentage {
        Percentage(points: Money.rounded(points, scale: 1))
    }

    /// numerator / denominator × 100, or nil when the denominator is zero.
    public static func ratio(_ numerator: Money, over denominator: Money) -> Percentage? {
        guard !denominator.isZero else { return nil }
        return computed(numerator.amount / denominator.amount * 100)
    }

    public var fraction: Decimal { points / 100 }
}

public extension Money {
    func multiplied(by percentage: Percentage) -> Money {
        multiplied(by: percentage.fraction)
    }
}
