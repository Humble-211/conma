import Foundation

public struct Photo: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public let projectId: UUID
    public var dailyLogId: UUID?
    public var category: PhotoCategory
    public var takenAt: Date
    public var latitude: Double? // lint:allow-double (coordinates, not money)
    public var longitude: Double? // lint:allow-double (coordinates, not money)
    public var filePath: String
    public var remotePath: String?
    public var caption: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, projectId: UUID, dailyLogId: UUID?, category: PhotoCategory, takenAt: Date, latitude: Double?, longitude: Double?, filePath: String, remotePath: String?, caption: String?, createdAt: Date, updatedAt: Date, deletedAt: Date?) { // lint:allow-double
        self.id = id; self.companyId = companyId; self.projectId = projectId; self.dailyLogId = dailyLogId; self.category = category
        self.takenAt = takenAt; self.latitude = latitude; self.longitude = longitude; self.filePath = filePath; self.remotePath = remotePath
        self.caption = caption; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}
