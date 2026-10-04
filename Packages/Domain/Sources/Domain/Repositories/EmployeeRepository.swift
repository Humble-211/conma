// Packages/Domain/Sources/Domain/Repositories/EmployeeRepository.swift
import Foundation

public protocol EmployeeRepository: Sendable {
    /// Live crew ordered by `CrewList.ordered`; emits on any change.
    func observeAll(companyId: UUID) -> AsyncThrowingStream<[Employee], Error>
    /// `includingDeleted: true` is for history (names of labour entries).
    func get(id: UUID, includingDeleted: Bool) async throws -> Employee?
    /// DomainError.emptyName / .negativeAmount / .currencyMismatch.
    func create(_ employee: Employee) async throws
    /// No-op when nothing changed. DomainError.notFound, DataError.scopeMismatch (other company).
    func update(_ employee: Employee) async throws
    /// Hides the person; their labour entries stay (Foundation A.2). DomainError.notFound.
    func softDelete(id: UUID) async throws
}
