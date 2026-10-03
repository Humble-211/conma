import Foundation

public struct EstimateLineChange: Equatable, Sendable {
    public let upserts: [ProjectEstimateLine]
    public let deletedIds: [UUID]
    public let totalBefore: Money
    public let totalAfter: Money
    public init(upserts: [ProjectEstimateLine], deletedIds: [UUID], totalBefore: Money, totalAfter: Money) {
        self.upserts = upserts; self.deletedIds = deletedIds; self.totalBefore = totalBefore; self.totalAfter = totalAfter
    }
}

public struct ScheduleItemChange: Equatable, Sendable {
    public let upserts: [PaymentScheduleItem]
    public let deletedIds: [UUID]
    public let totalBefore: Money
    public let totalAfter: Money
    public init(upserts: [PaymentScheduleItem], deletedIds: [UUID], totalBefore: Money, totalAfter: Money) {
        self.upserts = upserts; self.deletedIds = deletedIds; self.totalBefore = totalBefore; self.totalAfter = totalAfter
    }
}

public enum DraftDiffError: Error, Equatable { case lineOutsideGroup }

public enum DraftDiff {
    /// Spec 3.6. Only lines of `group` are considered on both sides.
    public static func estimateLines(group: CostGroup, old: [ProjectEstimateLine], new: [DraftEstimateLine], companyId: UUID, projectId: UUID, currency: CurrencyCode, now: Date) throws -> EstimateLineChange {
        guard new.allSatisfy({ $0.costGroup == group }) else { throw DraftDiffError.lineOutsideGroup }
        let oldInGroup = old.filter { $0.costGroup == group && !$0.isDeleted }
        let oldById = Dictionary(oldInGroup.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newIds = Set(new.map(\.id))
        let upserts = new.sorted { $0.sortOrder < $1.sortOrder }.enumerated().map { index, line -> ProjectEstimateLine in
            let amount: Money
            if let qty = line.quantity, let rate = line.unitRate { amount = rate.multiplied(by: qty) } else { amount = line.amount }
            return ProjectEstimateLine(id: line.id, companyId: companyId, projectId: projectId, costGroup: group, label: line.label, amount: amount,
                                       quantity: line.quantity, unitRate: line.unitRate, sortOrder: index,
                                       createdAt: oldById[line.id]?.createdAt ?? now, updatedAt: now, deletedAt: nil)
        }
        let deleted = oldInGroup.filter { !newIds.contains($0.id) }.map(\.id)
        return EstimateLineChange(upserts: upserts, deletedIds: deleted,
                                  totalBefore: try Money.sum(oldInGroup.map(\.amount), currency: currency),
                                  totalAfter: try Money.sum(upserts.map(\.amount), currency: currency))
    }

    public static func scheduleItems(old: [PaymentScheduleItem], new: [DraftScheduleRow], contract: Money, companyId: UUID, projectId: UUID, now: Date) throws -> ScheduleItemChange {
        let live = old.filter { !$0.isDeleted }
        let oldById = Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let rows = ScheduleMath.recompute(rows: new, contract: contract, edited: .none).rows
        let upserts = rows.filter { $0.amount != nil }.enumerated().compactMap { index, row -> PaymentScheduleItem? in
            guard let amount = row.amount else { return nil }
            return PaymentScheduleItem(id: row.id, companyId: companyId, projectId: projectId, label: row.label, amount: amount, percentage: row.percentage, dueDate: row.dueDate,
                                       triggerText: row.trigger, isDeposit: row.isDeposit, notes: oldById[row.id]?.notes, sortOrder: index,
                                       createdAt: oldById[row.id]?.createdAt ?? now, updatedAt: now, deletedAt: nil)
        }
        let keep = Set(upserts.map(\.id))
        let deleted = live.filter { !keep.contains($0.id) }.map(\.id)
        return ScheduleItemChange(upserts: upserts, deletedIds: deleted,
                                  totalBefore: try Money.sum(live.map(\.amount), currency: contract.currency),
                                  totalAfter: try Money.sum(upserts.map(\.amount), currency: contract.currency))
    }

    /// Returns the full replacement list for `project.scopeFields` (the repository soft-deletes what is missing).
    public static func scopeFields(old: [ProjectScopeField], new: [DraftScopeField], companyId: UUID, projectId: UUID, now: Date) -> [ProjectScopeField] {
        let oldById = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return new.filter { !$0.key.isBlank && !$0.value.isBlank }.sorted { $0.sortOrder < $1.sortOrder }.enumerated().map { index, f in
            ProjectScopeField(id: f.id, companyId: companyId, projectId: projectId, fieldKey: f.key, valueText: f.value, sortOrder: index,
                              createdAt: oldById[f.id]?.createdAt ?? now, updatedAt: now, deletedAt: nil)
        }
    }
}
