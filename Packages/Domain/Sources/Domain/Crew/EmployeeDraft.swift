import Foundation

public enum EmployeeDraftError: Hashable, Sendable, CaseIterable {
    case nameMissing, rateNegative
}

/// Crew member form (spec §3.2). Trade is the one "what they do" field (`role` stays nil in 3b).
public struct EmployeeDraft: Hashable, Sendable {
    /// Only for the "8 h × hourly" helper; labour is always logged in days.
    public static let hoursPerDay: Decimal = 8

    public var name: String
    public var trade: String
    public var phone: String
    public var notes: String
    public var dailyRate: Decimal?
    public var hourlyRate: Decimal?

    public init() { name = ""; trade = ""; phone = ""; notes = ""; dailyRate = nil; hourlyRate = nil }

    public init(editing employee: Employee) {
        name = employee.name
        trade = employee.trade ?? ""
        phone = employee.phone ?? ""
        notes = employee.notes ?? ""
        dailyRate = employee.dailyRate?.amount
        hourlyRate = employee.hourlyRate?.amount
    }

    public var errors: [EmployeeDraftError] {
        var result: [EmployeeDraftError] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.append(.nameMissing) }
        if (dailyRate ?? 0) < 0 || (hourlyRate ?? 0) < 0 { result.append(.rateNegative) }
        return result
    }

    public var canSave: Bool { errors.isEmpty }

    /// rounded(rounded(hourly) × 8); nil without an hourly rate.
    public var dailyFromHourly: Decimal? { hourlyRate.map { Money.rounded(Money.rounded($0) * Self.hoursPerDay) } }

    public func makeEmployee(id: UUID, companyId: UUID, currency: CurrencyCode, now: Date) throws -> Employee {
        try check()
        return Employee(id: id, companyId: companyId, name: trimmedName, phone: Self.clean(phone), role: nil, trade: Self.clean(trade),
                        hourlyRate: hourlyRate.map { Money($0, currency) }, dailyRate: dailyRate.map { Money($0, currency) },
                        certifications: nil, emergencyContact: nil, notes: Self.clean(notes), createdAt: now, updatedAt: now, deletedAt: nil)
    }

    /// Edit: keeps identity, creation time and the fields 3b does not show (role, certifications, emergency contact).
    public func apply(to existing: Employee, currency: CurrencyCode, now: Date) throws -> Employee {
        try check()
        var e = existing
        e.name = trimmedName
        e.trade = Self.clean(trade)
        e.phone = Self.clean(phone)
        e.notes = Self.clean(notes)
        e.dailyRate = dailyRate.map { Money($0, currency) }
        e.hourlyRate = hourlyRate.map { Money($0, currency) }
        e.updatedAt = now
        return e
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func check() throws {
        let found = errors
        if found.contains(.nameMissing) { throw DomainError.emptyName }
        if found.contains(.rateNegative) { throw DomainError.negativeAmount }
    }

    static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum CrewList {
    /// Live crew by name (Finder-style compare), then creation time.
    public static func ordered(_ employees: [Employee]) -> [Employee] {
        employees.filter { !$0.isDeleted }.sorted { a, b in
            let c = a.name.localizedStandardCompare(b.name)
            if c != .orderedSame { return c == .orderedAscending }
            return a.createdAt < b.createdAt
        }
    }
}
