import Foundation

public protocol PaymentScheduleRepository: Sendable {
    func items(projectId: UUID) async throws -> [PaymentScheduleItem]
    /// One transaction; deleted items' payments get schedule_item_id = NULL; logs `scheduleChanged` only when the total changed.
    func replace(projectId: UUID, change: ScheduleItemChange, actor: ActivityActor) async throws
}
