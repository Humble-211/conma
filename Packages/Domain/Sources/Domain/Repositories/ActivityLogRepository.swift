import Foundation

public protocol ActivityLogRepository: Sendable {
    func observeForProject(projectId: UUID, limit: Int) -> AsyncThrowingStream<[ActivityLogEntry], Error>   // occurredAt desc
    func list(projectId: UUID) async throws -> [ActivityLogEntry]                                            // occurredAt desc, all
}
