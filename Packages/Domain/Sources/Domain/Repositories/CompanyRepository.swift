import Foundation

public struct CompanySetup: Sendable, Hashable {
    public let company: Company
    public let owner: User

    public init(company: Company, owner: User) {
        self.company = company
        self.owner = owner
    }
}

public protocol CompanyRepository: Sendable {
    /// The single local company with its owner, or nil when setup has not completed.
    func current() async throws -> CompanySetup?
    func create(company: Company, owner: User) async throws
    func update(company: Company) async throws
}
