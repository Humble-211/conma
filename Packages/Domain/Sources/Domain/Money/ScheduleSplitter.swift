import Foundation

public enum ScheduleSplitter {
    /// Each line is `rounded(contract × fraction)`. When the percentages total exactly 100,
    /// the last line receives the residual so the lines sum to the contract to the cent.
    public static func amounts(of contract: Money, percentages: [Percentage]) -> [Money] {
        guard !percentages.isEmpty else { return [] }
        var lines = percentages.map { contract.multiplied(by: $0) }
        let totalPoints = percentages.reduce(Decimal(0)) { $0 + $1.points }
        if totalPoints == 100 {
            let allButLast = lines.dropLast().reduce(Decimal(0)) { $0 + $1.amount }
            lines[lines.count - 1] = Money(contract.amount - allButLast, contract.currency)
        }
        return lines
    }
}
