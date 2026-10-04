import Foundation

/// Receipt pages after an edit: existing pages kept (in their new order) followed by new JPEG pages.
public struct ReceiptChange: Hashable, Sendable {
    public var keptImageIds: [UUID]
    public var newPages: [Data]
    public init(keptImageIds: [UUID], newPages: [Data]) { self.keptImageIds = keptImageIds; self.newPages = newPages }
}

public protocol ExpenseRepository: Sendable {
    /// Live projects, live expenses (with live receipts) and every custom category of the company; emits on any change.
    func observeAll(companyId: UUID) -> AsyncThrowingStream<ExpenseListSnapshot, Error>
    /// nil when missing or soft-deleted; includes live receipts.
    func get(id: UUID) async throws -> Expense?
    /// Writes the JPEGs, then expense + receipt rows + `expenseAdded` in one transaction (files removed if it fails).
    /// Throws DomainError.notFound (project or custom category not live), .currencyMismatch, .tooManyReceiptPages.
    func create(_ expense: Expense, receiptPages: [Data], actor: ActivityActor) async throws
    /// No-op when nothing changed; otherwise `expenseUpdated` in the same transaction.
    func update(_ expense: Expense, receipts: ReceiptChange, actor: ActivityActor) async throws
    /// Soft-deletes the expense and its receipt rows (files stay) and logs `expenseDeleted`.
    func softDelete(id: UUID, actor: ActivityActor) async throws
    func fileURL(for image: ReceiptImage) -> URL
}
