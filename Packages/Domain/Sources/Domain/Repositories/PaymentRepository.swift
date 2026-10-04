// Packages/Domain/Sources/Domain/Repositories/PaymentRepository.swift
import Foundation

public protocol PaymentRepository: Sendable {
    /// nil when missing or soft-deleted.
    func get(id: UUID) async throws -> Payment?
    /// Method of the company's most recently created live payment; nil when there is none.
    func lastUsedMethod(companyId: UUID) async throws -> PaymentMethod?
    /// Payment + `paymentReceived` in one transaction. Throws DomainError.invalidPaymentAmount, .currencyMismatch,
    /// .notFound (project not live, or the schedule item not live / not of this project).
    func create(_ payment: Payment, actor: ActivityActor) async throws
    /// No-op when nothing changed; otherwise `paymentUpdated` (with "from"). DataError.scopeMismatch when company/project changed.
    func update(_ payment: Payment, actor: ActivityActor) async throws
    /// Soft delete + `paymentDeleted`. DomainError.notFound when missing.
    func softDelete(id: UUID, actor: ActivityActor) async throws
}
