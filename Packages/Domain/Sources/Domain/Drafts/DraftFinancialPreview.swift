import Foundation

public struct DraftFinancialPreview: Equatable, Sendable {
    public let estimateByGroup: [CostGroup: Money]
    public let estimatedCost: Money
    public let projectedProfit: Money?
    public let projectedMargin: Percentage?
    public let scheduleTotal: Money
    public let scheduleWarning: ScheduleWarning?
    public let depositAmount: Money?

    /// Spec 3.4. Pure; uses the same sums the assembler will persist.
    public static func compute(_ draft: ProjectDraft, currency: CurrencyCode) -> DraftFinancialPreview {
        let zero = Money.zero(currency)
        let lines = draft.allEstimateLines(currency: currency)
        var byGroup: [CostGroup: Money] = [:]
        for line in lines where line.amount.currency == currency {
            byGroup[line.costGroup] = (try? (byGroup[line.costGroup] ?? zero).adding(line.amount)) ?? byGroup[line.costGroup]
        }
        let estimatedCost = byGroup.values.reduce(zero) { (try? $0.adding($1)) ?? $0 }
        let contract = draft.contractValue
        let profit = contract.flatMap { try? $0.subtracting(estimatedCost) }
        let margin = contract.flatMap { c in profit.flatMap { Percentage.ratio($0, over: c) } }
        let schedule = ScheduleMath.recompute(rows: draft.schedule, contract: contract ?? zero, edited: .none)
        let deposit: Money? = draft.deposit.flatMap { dep in
            switch dep.mode {
            case .fixed(let m): return m
            case .percentage(let p): return contract?.multiplied(by: p)
            }
        }
        return DraftFinancialPreview(estimateByGroup: byGroup, estimatedCost: estimatedCost, projectedProfit: profit, projectedMargin: margin,
                                     scheduleTotal: schedule.total, scheduleWarning: draft.schedule.isEmpty ? nil : schedule.warning, depositAmount: deposit)
    }
}

public extension ProjectDraft {
    /// Labour (quick or detailed) + material + other, amounts re-derived from rate × quantity where both exist.
    func allEstimateLines(currency: CurrencyCode) -> [DraftEstimateLine] {
        var result: [DraftEstimateLine] = []
        switch labourMode {
        case .quick:
            if let q = labourQuick, let workers = q.workers, let rate = q.dailyRate, let days = q.days, workers > 0, days > 0 {
                let quantity = Decimal(workers) * days
                result.append(DraftEstimateLine(id: UUID(), label: "schedule.row.labourQuick", amount: rate.multiplied(by: quantity), quantity: quantity,
                                                unitRate: rate, costGroup: .labour, otherKind: nil, sortOrder: 0))
            }
        case .detailed:
            result.append(contentsOf: labourLines.map(Self.recomputed))
        }
        result.append(contentsOf: materialLines.map(Self.recomputed))
        result.append(contentsOf: otherLines.map(Self.recomputed))
        return result
    }

    private static func recomputed(_ line: DraftEstimateLine) -> DraftEstimateLine {
        guard let qty = line.quantity, let rate = line.unitRate else { return line }
        var copy = line
        copy.amount = rate.multiplied(by: qty)
        return copy
    }
}
