import Foundation

public enum EditedField: Equatable, Sendable { case percentage(Int), amount(Int), rescale, none }

public enum ScheduleWarning: Equatable, Sendable {
    case totalMismatch(difference: Money)
    case contractZero
    case currencyMismatch
}

public struct ScheduleResult: Equatable, Sendable {
    public let rows: [DraftScheduleRow]
    public let total: Money
    public let warning: ScheduleWarning?
}

public enum ScheduleMath {
    /// Spec 3.3 (+ errata). Percent edits and `.rescale` re-derive every amount from percentages
    /// (residual on the last row when they total 100); an amount edit re-derives only that row's
    /// percentage. `.none` is fill-only: a typed amount is authoritative and is never overwritten;
    /// only rows with a percentage and no amount are filled (all of them, with residual, when none
    /// has an amount yet, i.e. a template was just applied).
    public static func recompute(rows: [DraftScheduleRow], contract: Money, edited: EditedField) -> ScheduleResult {
        var rows = rows
        let currency = contract.currency
        switch edited {
        case .amount(let i):
            if rows.indices.contains(i), let amount = rows[i].amount {
                rows[i].percentage = contract.isZero ? nil : Percentage.ratio(amount, over: contract)
            }
        case .percentage, .rescale:
            rescaleAll(&rows, contract)
        case .none:
            let withPct = rows.indices.filter { rows[$0].percentage != nil }
            if withPct.allSatisfy({ rows[$0].amount == nil }) {
                rescaleAll(&rows, contract)
            } else {
                for index in withPct where rows[index].amount == nil {
                    if let pct = rows[index].percentage { rows[index].amount = contract.multiplied(by: pct) }
                }
            }
        }
        let hasMismatch = rows.contains { ($0.amount?.currency ?? currency) != currency }
        let total = rows.reduce(Money.zero(currency)) { acc, row in
            guard let amount = row.amount, amount.currency == currency, let sum = try? acc.adding(amount) else { return acc }
            return sum
        }
        var warning: ScheduleWarning?
        if hasMismatch {
            warning = .currencyMismatch
        } else if contract.isZero, rows.contains(where: { $0.percentage != nil }) {
            warning = .contractZero
        } else if !rows.isEmpty, total != contract, let diff = try? total.subtracting(contract) {
            warning = .totalMismatch(difference: diff)
        }
        return ScheduleResult(rows: rows, total: total, warning: warning)
    }

    private static func rescaleAll(_ rows: inout [DraftScheduleRow], _ contract: Money) {
        let withPct = rows.indices.filter { rows[$0].percentage != nil }
        let pcts = withPct.compactMap { rows[$0].percentage }
        let amounts = ScheduleSplitter.amounts(of: contract, percentages: pcts)
        for (k, index) in withPct.enumerated() { rows[index].amount = amounts[k] }
    }

    /// Errata (I3): the deposit the contractor typed drives the `isDeposit` row.
    /// Fixed: that row gets the amount; the other percentage rows split `contract - fixed` in their
    /// existing proportions (residual on the last). Percentage: that row takes the percentage and the
    /// others share the remaining points. No-op without a deposit or deposit row; a fixed deposit larger than the
    /// contract sets only the deposit row (the others keep their template percentages), so the
    /// total-mismatch warning shows; a currency mismatch leaves the rows as they are.
    public static func applyDeposit(rows: [DraftScheduleRow], contract: Money, deposit: DraftDeposit?) -> [DraftScheduleRow] {
        guard let deposit, let depositIndex = rows.firstIndex(where: \.isDeposit) else { return rows }
        var rows = rows
        let others = rows.indices.filter { $0 != depositIndex && rows[$0].percentage != nil }
        let weights = others.compactMap { rows[$0].percentage?.points }
        let weightSum = weights.reduce(Decimal(0), +)
        switch deposit.mode {
        case .percentage(let p):
            rows[depositIndex].percentage = p
            if weightSum > 0 {
                let remainder = 100 - p.points
                var split = weights.map { Money.rounded(remainder * $0 / weightSum, scale: 2) }
                let allButLast = split.dropLast().reduce(Decimal(0), +)
                split[split.count - 1] = remainder - allButLast
                for (k, index) in others.enumerated() { rows[index].percentage = Percentage.exact(split[k]) }
            }
            return recompute(rows: rows, contract: contract, edited: .rescale).rows
        case .fixed(let m):
            guard m.currency == contract.currency, !m.isNegative else { return rows }
            rows[depositIndex].amount = m
            rows[depositIndex].percentage = Percentage.ratio(m, over: contract)
            if weightSum > 0, contract.amount - m.amount >= 0 {
                let remainder = contract.amount - m.amount
                var split = weights.map { Money.rounded(remainder * $0 / weightSum) }
                let allButLast = split.dropLast().reduce(Decimal(0), +)
                split[split.count - 1] = remainder - allButLast
                for (k, index) in others.enumerated() {
                    let amount = Money(split[k], contract.currency)
                    rows[index].amount = amount
                    rows[index].percentage = Percentage.ratio(amount, over: contract)
                }
            }
            return rows
        }
    }
}
