// CustomerProfileViewModel.swift
import Foundation
import Observation
import Domain

@Observable
@MainActor
public final class CustomerProfileViewModel {
    public private(set) var customer: Customer?
    public private(set) var projects: [Project] = []
    public private(set) var isLoaded = false
    private let customerId: UUID
    private let customerRepository: any CustomerRepository

    public init(customerId: UUID, customerRepository: any CustomerRepository) { self.customerId = customerId; self.customerRepository = customerRepository }

    public func load() async {
        customer = try? await customerRepository.get(id: customerId)
        projects = (try? await customerRepository.projects(customerId: customerId)) ?? []
        isLoaded = true
    }
}
