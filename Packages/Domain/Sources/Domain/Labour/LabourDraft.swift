import Foundation

public enum LabourDraftError: Hashable, Sendable, CaseIterable {
    case noCrewSelected, daysMissing, daysNotPositive, rateMissing, rateNegative
}

/// One selected person and the daily rate that will be snapshotted on their entry.
public struct LabourLine: Hashable, Sendable, Identifiable {
    public let employeeId: UUID
    public var dailyRate: Decimal?
    public var id: UUID { employeeId }
    public init(employeeId: UUID, dailyRate: Decimal?) { self.employeeId = employeeId; self.dailyRate = dailyRate }
}

/// "Log labour" (spec §3.3): one date and one days value for every selected person; one entry per person.
public struct LabourDraft: Hashable, Sendable {
    public static let dayStep: Decimal = Decimal(5) / Decimal(10)

    public var workDate: CalendarDate
    public var days: Decimal?
    public var lines: [LabourLine]
    public var notes: String

    public init(workDate: CalendarDate) {
        self.workDate = workDate; days = 1; lines = []; notes = ""
    }

    public init(editing entry: LabourEntry) {
        workDate = entry.workDate
        days = entry.days
        lines = [LabourLine(employeeId: entry.employeeId, dailyRate: entry.dailyRate.amount)]
        notes = entry.notes ?? ""
    }

    public func isSelected(_ employeeId: UUID) -> Bool { lines.contains { $0.employeeId == employeeId } }

    /// Selects with the employee's current daily rate (nil when they have none), or deselects.
    public mutating func toggle(_ employee: Employee) {
        if let index = lines.firstIndex(where: { $0.employeeId == employee.id }) { lines.remove(at: index) }
        else { lines.append(LabourLine(employeeId: employee.id, dailyRate: employee.dailyRate?.amount)) }
    }

    public mutating func setRate(_ rate: Decimal?, for employeeId: UUID) {
        guard let index = lines.firstIndex(where: { $0.employeeId == employeeId }) else { return }
        lines[index].dailyRate = rate
    }

    /// ± half a day; never below half a day.
    public mutating func stepDays(up: Bool) {
        let next = (days ?? 0) + (up ? Self.dayStep : -Self.dayStep)
        days = max(Self.dayStep, next)
    }

    /// rounded(days × rate): the same single rounding as `LabourEntry.cost`.
    public func cost(for employeeId: UUID, currency: CurrencyCode) -> Money? {
        guard let days, days > 0, let rate = lines.first(where: { $0.employeeId == employeeId })?.dailyRate, Money.rounded(rate) >= 0 else { return nil }
        return LabourEntry.cost(days: days, dailyRate: Money(rate, currency))
    }

    /// Sum of the rounded per-person costs; nil while nobody is selected or a line cannot be costed.
    public func total(currency: CurrencyCode) -> Money? {
        guard !lines.isEmpty else { return nil }
        var sum = Money.zero(currency)
        for line in lines {
            guard let cost = cost(for: line.employeeId, currency: currency), let next = try? sum.adding(cost) else { return nil }
            sum = next
        }
        return sum
    }

    public func lineError(for employeeId: UUID) -> LabourDraftError? {
        guard let line = lines.first(where: { $0.employeeId == employeeId }) else { return nil }
        guard let rate = line.dailyRate else { return .rateMissing }
        return Money.rounded(rate) < 0 ? .rateNegative : nil
    }

    /// In declaration order of `LabourDraftError`.
    public var errors: [LabourDraftError] {
        var result: [LabourDraftError] = []
        if lines.isEmpty { result.append(.noCrewSelected) }
        if let days {
            if days <= 0 { result.append(.daysNotPositive) }
        } else {
            result.append(.daysMissing)
        }
        let lineErrors = Set(lines.compactMap { lineError(for: $0.employeeId) })
        if lineErrors.contains(.rateMissing) { result.append(.rateMissing) }
        if lineErrors.contains(.rateNegative) { result.append(.rateNegative) }
        return result
    }

    public var canSave: Bool { errors.isEmpty }

    public func makeEntries(companyId: UUID, projectId: UUID, currency: CurrencyCode, now: Date, makeId: () -> UUID = { UUID() }) throws -> [LabourEntry] {
        guard canSave, let days else { throw DomainError.incompleteLabour }
        let note = Self.clean(notes)
        return lines.map { line in
            LabourEntry(id: makeId(), companyId: companyId, projectId: projectId, employeeId: line.employeeId, workDate: workDate, days: days,
                        dailyRate: Money(line.dailyRate ?? 0, currency), notes: note, createdAt: now, updatedAt: now, deletedAt: nil)
        }
    }

    /// Edit one entry: date, days, rate and notes change; the person never does.
    public func apply(to existing: LabourEntry, now: Date) throws -> LabourEntry {
        guard canSave, let days, let rate = lines.first(where: { $0.employeeId == existing.employeeId })?.dailyRate else { throw DomainError.incompleteLabour }
        var entry = existing
        entry.workDate = workDate
        entry.days = days
        entry.dailyRate = Money(rate, existing.dailyRate.currency)
        entry.notes = Self.clean(notes)
        entry.updatedAt = now
        return entry
    }

    /// Days already logged for this person on this day (live entries of the project; `excluding` = the entry being edited).
    public static func alreadyLoggedDays(employeeId: UUID, on day: CalendarDate, entries: [LabourEntry], excluding entryId: UUID?) -> Decimal {
        entries.filter { !$0.isDeleted && $0.employeeId == employeeId && $0.workDate == day && $0.id != entryId }
            .reduce(Decimal(0)) { $0 + $1.days }
    }

    static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
