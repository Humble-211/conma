import Foundation

public enum EditedField: Equatable, Sendable { case percentage(Int), amount(Int), none }

public enum ScheduleWarning: Equatable, Sendable {
    case totalMismatch(difference: Money)
    case contractZero
}

public struct ScheduleResult: Equatable, Sendable {
    public let rows: [DraftScheduleRow]
    public let total: Money
    public let warning: ScheduleWarning?
}

public enum ScheduleMath {
    /// Spec 3.3. Percent edits re-derive every amount from percentages (residual on the last row
    /// when they total 100); an amount edit re-derives only that row's percentage.
    public static func recompute(rows: [DraftScheduleRow], contract: Money, edited: EditedField) -> ScheduleResult {
        var rows = rows
        let currency = contract.currency
        switch edited {
        case .amount(let i):
            if rows.indices.contains(i), let amount = rows[i].amount {
                rows[i].percentage = contract.isZero ? nil : Percentage.ratio(amount, over: contract)
            }
        case .percentage, .none:
            let withPct = rows.indices.filter { rows[$0].percentage != nil }
            let pcts = withPct.compactMap { rows[$0].percentage }
            let amounts = ScheduleSplitter.amounts(of: contract, percentages: pcts)
            for (k, index) in withPct.enumerated() { rows[index].amount = amounts[k] }
        }
        let total = rows.reduce(Money.zero(currency)) { acc, row in
            guard let amount = row.amount, let sum = try? acc.adding(amount) else { return acc }
            return sum
        }
        var warning: ScheduleWarning?
        if contract.isZero, rows.contains(where: { $0.percentage != nil }) {
            warning = .contractZero
        } else if !rows.isEmpty, total != contract, let diff = try? total.subtracting(contract) {
            warning = .totalMismatch(difference: diff)
        }
        return ScheduleResult(rows: rows, total: total, warning: warning)
    }
}
