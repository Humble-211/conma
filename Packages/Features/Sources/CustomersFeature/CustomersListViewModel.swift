// CustomersListViewModel.swift
import Foundation
import Observation
import SwiftUI
import Domain

public enum DeleteOutcome: Equatable, Sendable { case deleted, hasProjects, failed }

@Observable
@MainActor
public final class CustomersListViewModel {
    public private(set) var customers: [Customer] = []
    public private(set) var isLoaded = false
    public var query = ""
    public var errorKey: LocalizedStringKey?
    public let companyId: UUID
    private let customerRepository: any CustomerRepository
    private let actor: ActivityActor

    public init(customerRepository: any CustomerRepository, companyId: UUID, actor: ActivityActor) {
        self.customerRepository = customerRepository; self.companyId = companyId; self.actor = actor
    }

    public func start() async {
        do { for try await value in customerRepository.observeAll(companyId: companyId) { customers = value; isLoaded = true } }
        catch is CancellationError {} catch { errorKey = "customers.error" }
    }

    public var visible: [Customer] {
        let q = SearchFold.normalize(query)
        guard !q.isEmpty else { return customers }
        return customers.filter { c in [c.name, c.phone ?? "", c.email ?? "", c.companyName ?? ""].contains { SearchFold.normalize($0).contains(q) } }
    }

    public func save(_ customer: Customer) async -> Bool {
        do { try await customerRepository.save(customer); return true } catch { errorKey = "customers.saveFailed"; return false }
    }

    public func delete(_ id: UUID) async -> DeleteOutcome {
        do { try await customerRepository.softDelete(id: id, actor: actor); return .deleted }
        catch DomainError.customerHasProjects { return .hasProjects }
        catch { return .failed }
    }
}
