import Foundation

public struct DailyLog: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public let projectId: UUID
    public var logDate: CalendarDate
    public var workersOnsite: Int?
    public var weather: String?
    public var workCompleted: String?
    public var materialDelivered: String?
    public var problems: String?
    public var tomorrowPlan: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, projectId: UUID, logDate: CalendarDate, workersOnsite: Int?, weather: String?, workCompleted: String?, materialDelivered: String?, problems: String?, tomorrowPlan: String?, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.projectId = projectId; self.logDate = logDate; self.workersOnsite = workersOnsite
        self.weather = weather; self.workCompleted = workCompleted; self.materialDelivered = materialDelivered; self.problems = problems
        self.tomorrowPlan = tomorrowPlan; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}
