import Foundation

public struct Customer: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public var name: String
    public var phone: String?
    public var email: String?
    public var preferredContact: ContactMethod?
    public var companyName: String?
    public var secondaryContact: String?
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, name: String, phone: String?, email: String?, preferredContact: ContactMethod?, companyName: String?, secondaryContact: String?, notes: String?, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.name = name; self.phone = phone; self.email = email
        self.preferredContact = preferredContact; self.companyName = companyName; self.secondaryContact = secondaryContact
        self.notes = notes; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public func validate() throws {
        if name.isBlank { throw DomainError.emptyName }
    }
}
