import Foundation

public extension PaymentScheduleTemplate {
    /// Base rows as (label key, percentage points). First row is the deposit.
    private var base: [(String, Decimal)] {
        switch self {
        case .depositFinal: return [("schedule.row.deposit", 30), ("schedule.row.final", 70)]
        case .depositProgressFinal: return [("schedule.row.deposit", 30), ("schedule.row.progress", 40), ("schedule.row.final", 30)]
        case .fourStage: return [("schedule.row.deposit", 20), ("schedule.row.stage2", 30), ("schedule.row.stage3", 30), ("schedule.row.final", 20)]
        case .custom: return []
        }
    }

    /// Spec 3.2: when a deposit percentage is given, the first row takes it and the remainder is
    /// split across the other rows in the template's proportions; the last row absorbs rounding.
    func rows(depositPercentage: Percentage?) -> [DraftScheduleRow] {
        if self == .custom {
            guard let deposit = depositPercentage else { return [] }
            return [DraftScheduleRow(id: UUID(), label: "schedule.row.deposit", percentage: deposit, amount: nil, dueDate: nil, trigger: nil, isDeposit: true)]
        }
        var points = base.map(\.1)
        if let deposit = depositPercentage?.points {
            let remainder = 100 - deposit
            let weights = Array(points.dropFirst())
            let weightSum = weights.reduce(Decimal(0), +)
            var split = weights.map { Money.rounded(remainder * $0 / weightSum, scale: 2) }
            if !split.isEmpty {
                let allButLast = split.dropLast().reduce(Decimal(0), +)
                split[split.count - 1] = remainder - allButLast
            }
            points = [deposit] + split
        }
        return zip(base, points).enumerated().map { index, pair in
            let (labelKey, pct) = (pair.0.0, pair.1)
            return DraftScheduleRow(id: UUID(), label: labelKey, percentage: Percentage.exact(pct), amount: nil, dueDate: nil, trigger: nil, isDeposit: index == 0)
        }
    }
}
