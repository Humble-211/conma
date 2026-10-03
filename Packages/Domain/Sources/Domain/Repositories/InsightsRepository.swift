import Foundation

public protocol InsightsRepository: Sendable {
    /// Live company snapshot (every related table, non-deleted rows); emits on any change.
    func observeDashboard(companyId: UUID) -> AsyncThrowingStream<DashboardInputs.Snapshot, Error>
    /// nil when the project is missing or soft-deleted.
    func observeProject(id: UUID) -> AsyncThrowingStream<ProjectInsightsInputs.Snapshot?, Error>
}
