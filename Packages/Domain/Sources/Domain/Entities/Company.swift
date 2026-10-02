import Foundation

public struct Company: Entity {
    public let id: UUID
    public var name: String
    public var currencyCode: CurrencyCode
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, name: String, currencyCode: CurrencyCode, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.name = name; self.currencyCode = currencyCode
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public func validate() throws {
        if name.isBlank { throw DomainError.emptyName }
    }
}
