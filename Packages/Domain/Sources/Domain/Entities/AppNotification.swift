import Foundation

public struct AppNotification: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public var projectId: UUID?
    public var kind: String
    public var entityType: String?
    public var entityId: UUID?
    public var detailsJSON: String
    public var fireAt: Date
    public var readAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, projectId: UUID?, kind: String, entityType: String?, entityId: UUID?, detailsJSON: String, fireAt: Date, readAt: Date?, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.projectId = projectId; self.kind = kind; self.entityType = entityType
        self.entityId = entityId; self.detailsJSON = detailsJSON; self.fireAt = fireAt; self.readAt = readAt
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}
