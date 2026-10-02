import Foundation

public struct Employee: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public var name: String
    public var phone: String?
    public var role: String?
    public var trade: String?
    public var hourlyRate: Money?
    public var dailyRate: Money?
    public var certifications: String?
    public var emergencyContact: String?
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, name: String, phone: String?, role: String?, trade: String?, hourlyRate: Money?, dailyRate: Money?, certifications: String?, emergencyContact: String?, notes: String?, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.name = name; self.phone = phone; self.role = role; self.trade = trade
        self.hourlyRate = hourlyRate; self.dailyRate = dailyRate; self.certifications = certifications; self.emergencyContact = emergencyContact
        self.notes = notes; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public func validate() throws {
        if name.isBlank { throw DomainError.emptyName }
        if hourlyRate?.isNegative == true || dailyRate?.isNegative == true { throw DomainError.negativeAmount }
    }
}
