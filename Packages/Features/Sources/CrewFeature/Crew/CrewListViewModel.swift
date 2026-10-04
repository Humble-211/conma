import Foundation
import Observation
import SwiftUI
import Domain

@Observable
@MainActor
public final class CrewListViewModel {
    public private(set) var employees: [Employee] = []
    public private(set) var isLoaded = false
    public var errorKey: LocalizedStringKey?
    public let currency: CurrencyCode
    private let companyId: UUID
    private let repository: any EmployeeRepository

    public init(employeeRepository: any EmployeeRepository, companyId: UUID, currency: CurrencyCode) {
        self.repository = employeeRepository; self.companyId = companyId; self.currency = currency
    }

    public func start() async {
        do {
            for try await value in repository.observeAll(companyId: companyId) { employees = value; isLoaded = true }
        } catch is CancellationError {
        } catch { errorKey = "crew.error" }
    }

    public func create(_ draft: EmployeeDraft) async -> LocalizedStringKey? {
        await run { try await self.repository.create(try draft.makeEmployee(id: UUID(), companyId: self.companyId, currency: self.currency, now: Date())) }
    }
    public func update(_ employee: Employee, with draft: EmployeeDraft) async -> LocalizedStringKey? {
        await run { try await self.repository.update(try draft.apply(to: employee, currency: self.currency, now: Date())) }
    }
    public func delete(_ id: UUID) async -> LocalizedStringKey? { await run { try await self.repository.softDelete(id: id) } }

    private func run(_ work: () async throws -> Void) async -> LocalizedStringKey? {
        do { try await work(); return nil } catch { return Self.key(for: error) }
    }

    public static func key(for error: Error) -> LocalizedStringKey {
        switch error as? DomainError {
        case .emptyName?: return "crew.error.nameMissing"
        case .negativeAmount?: return "crew.error.rateNegative"
        case .notFound?: return "crew.error.gone"
        default: return "crew.error.saveFailed"
        }
    }
}
