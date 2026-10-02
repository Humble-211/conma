import Foundation

public struct User: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public var displayName: String
    public var email: String?
    public var role: UserRole
    public var authUserId: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, displayName: String, email: String?, role: UserRole, authUserId: String?, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.displayName = displayName; self.email = email; self.role = role
        self.authUserId = authUserId; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public func validate() throws {
        if displayName.isBlank { throw DomainError.emptyName }
    }
}
