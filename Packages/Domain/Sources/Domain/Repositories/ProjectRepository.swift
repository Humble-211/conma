import Foundation

public struct ProjectSummary: Sendable, Hashable, Identifiable {
    public let project: Project
    public let customerName: String

    public var id: UUID { project.id }

    public init(project: Project, customerName: String) {
        self.project = project
        self.customerName = customerName
    }
}

public protocol ProjectRepository: Sendable {
    func get(id: UUID) async throws -> Project?
    func list(companyId: UUID) async throws -> [Project]
    /// Live, non-deleted projects with customer name, ordered by updatedAt desc. Emits on every change.
    func observeSummaries(companyId: UUID) -> AsyncThrowingStream<[ProjectSummary], Error>
    /// Insert or update, including scope fields; writes activity log rows for creation,
    /// contract value, status and manual progress changes, in the same transaction.
    func save(_ project: Project, actor: ActivityActor) async throws
    /// Cascading soft delete per spec A.2.
    func softDelete(id: UUID, actor: ActivityActor) async throws
}
