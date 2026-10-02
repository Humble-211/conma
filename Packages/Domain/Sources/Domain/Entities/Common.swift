import Foundation

public protocol Entity: Identifiable, Hashable, Sendable, Codable {
    var id: UUID { get }
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
}

public protocol CompanyScoped: Entity {
    var companyId: UUID { get }
}

public extension Entity {
    var isDeleted: Bool { deletedAt != nil }
}

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
