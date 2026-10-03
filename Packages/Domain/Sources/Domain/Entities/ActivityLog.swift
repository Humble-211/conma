import Foundation

/// Stable action codes; the UI renders a localized sentence from `action` + `details`.
public enum ActivityAction: String, Codable, Sendable, CaseIterable, Hashable {
    case projectCreated, projectDeleted, contractValueChanged, progressChanged, statusChanged
    case expenseAdded, paymentReceived
    case estimateChanged, scheduleChanged, customerCreated, scopeChanged, timelineChanged
}

public struct ActivityLogEntry: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public var userId: UUID?
    public var actorName: String
    public var action: ActivityAction
    public var entityType: String
    public var entityId: UUID
    public var projectId: UUID?
    /// JSON object text, e.g. {"from":"30000.00","to":"37500.00"}.
    public var detailsJSON: String
    public var occurredAt: Date
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, userId: UUID?, actorName: String, action: ActivityAction, entityType: String, entityId: UUID, projectId: UUID?, detailsJSON: String, occurredAt: Date, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.userId = userId; self.actorName = actorName; self.action = action
        self.entityType = entityType; self.entityId = entityId; self.projectId = projectId; self.detailsJSON = detailsJSON
        self.occurredAt = occurredAt; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}
