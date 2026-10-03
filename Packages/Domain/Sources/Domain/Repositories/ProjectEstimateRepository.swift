import Foundation

public protocol ProjectEstimateRepository: Sendable {
    func lines(projectId: UUID) async throws -> [ProjectEstimateLine]
    /// Applies the change in one transaction; logs `estimateChanged` only when totalBefore != totalAfter.
    func replace(projectId: UUID, group: CostGroup, change: EstimateLineChange, actor: ActivityActor) async throws
}
