import Foundation

public protocol CustomerRepository: Sendable {
    func get(id: UUID) async throws -> Customer?
    func list(companyId: UUID) async throws -> [Customer]
    func save(_ customer: Customer) async throws
    func softDelete(id: UUID, actor: ActivityActor) async throws
}
