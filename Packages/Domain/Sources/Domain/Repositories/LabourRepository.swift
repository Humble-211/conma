// Packages/Domain/Sources/Domain/Repositories/LabourRepository.swift
import Foundation

public struct ProjectLabourSnapshot: Hashable, Sendable {
    public var currency: CurrencyCode
    /// Live entries of the project.
    public var entries: [LabourEntry]
    /// Every employee of the company, deleted ones included (names of history rows).
    public var employees: [Employee]
    public init(currency: CurrencyCode, entries: [LabourEntry], employees: [Employee]) { self.currency = currency; self.entries = entries; self.employees = employees }
}

public protocol LabourRepository: Sendable {
    /// nil when the project is missing or soft-deleted; emits on any change.
    func observeProject(id: UUID) -> AsyncThrowingStream<ProjectLabourSnapshot?, Error>
    /// nil when missing or soft-deleted.
    func get(id: UUID) async throws -> LabourEntry?
    /// All entries + ONE `labourLogged` in one transaction, or nothing. DomainError.incompleteLabour (empty), .invalidLabourDays,
    /// .negativeAmount, .currencyMismatch, .notFound (project or an employee not live); DataError.scopeMismatch (mixed projects).
    func create(_ entries: [LabourEntry], actor: ActivityActor) async throws
    /// No-op when nothing changed; otherwise `labourUpdated`. DataError.scopeMismatch when company/project/employee changed.
    func update(_ entry: LabourEntry, actor: ActivityActor) async throws
    /// Soft delete + `labourDeleted`. DomainError.notFound.
    func softDelete(id: UUID, actor: ActivityActor) async throws
}
