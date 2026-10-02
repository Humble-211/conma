import Foundation

public struct TaskChecklistItem: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public let taskId: UUID
    public var title: String
    public var isDone: Bool
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, taskId: UUID, title: String, isDone: Bool, sortOrder: Int, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.taskId = taskId; self.title = title; self.isDone = isDone
        self.sortOrder = sortOrder; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}

public struct ProjectTask: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public let projectId: UUID
    public var name: String
    public var status: TaskStatus
    public var startDate: CalendarDate?
    public var dueDate: CalendarDate?
    public var notes: String?
    public var sortOrder: Int
    /// Employee ids, stored in `task_assignees`.
    public var assignees: [UUID]
    public var checklist: [TaskChecklistItem]
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, projectId: UUID, name: String, status: TaskStatus, startDate: CalendarDate?, dueDate: CalendarDate?, notes: String?, sortOrder: Int, assignees: [UUID], checklist: [TaskChecklistItem], createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.projectId = projectId; self.name = name; self.status = status
        self.startDate = startDate; self.dueDate = dueDate; self.notes = notes; self.sortOrder = sortOrder
        self.assignees = assignees; self.checklist = checklist; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}

public struct ProjectWorker: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public let projectId: UUID
    public let employeeId: UUID
    public var workDate: CalendarDate
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, projectId: UUID, employeeId: UUID, workDate: CalendarDate, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.projectId = projectId; self.employeeId = employeeId; self.workDate = workDate
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}
