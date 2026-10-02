import Foundation

public struct Address: Hashable, Sendable, Codable {
    public var line: String
    public var unit: String?
    public var city: String?
    public var region: String?
    public var postalCode: String?

    public init(line: String, unit: String?, city: String?, region: String?, postalCode: String?) {
        self.line = line; self.unit = unit; self.city = city; self.region = region; self.postalCode = postalCode
    }
}

public struct ProjectScopeField: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public let projectId: UUID
    public var fieldKey: String
    public var valueText: String
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, projectId: UUID, fieldKey: String, valueText: String, sortOrder: Int, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.projectId = projectId; self.fieldKey = fieldKey; self.valueText = valueText
        self.sortOrder = sortOrder; self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }
}

public struct Project: CompanyScoped {
    public let id: UUID
    public let companyId: UUID
    public var customerId: UUID
    public var name: String
    public var jobType: JobType
    public var customJobType: String?
    public var status: ProjectStatus
    public var address: Address
    public var scopeDescription: String?
    public var scopeFields: [ProjectScopeField]
    public var startDate: CalendarDate?
    public var estimatedCompletionDate: CalendarDate?
    public var workingDays: Int?
    public var hoursPerDay: Decimal?
    public var workersPerDay: Int?
    public var contractValue: Money
    /// 0...100; when set it overrides task-based progress.
    public var manualProgress: Int?
    public var depositRequiredToStart: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, companyId: UUID, customerId: UUID, name: String, jobType: JobType, customJobType: String?, status: ProjectStatus, address: Address, scopeDescription: String?, scopeFields: [ProjectScopeField], startDate: CalendarDate?, estimatedCompletionDate: CalendarDate?, workingDays: Int?, hoursPerDay: Decimal?, workersPerDay: Int?, contractValue: Money, manualProgress: Int?, depositRequiredToStart: Bool, createdAt: Date, updatedAt: Date, deletedAt: Date?) {
        self.id = id; self.companyId = companyId; self.customerId = customerId; self.name = name; self.jobType = jobType
        self.customJobType = customJobType; self.status = status; self.address = address; self.scopeDescription = scopeDescription
        self.scopeFields = scopeFields; self.startDate = startDate; self.estimatedCompletionDate = estimatedCompletionDate
        self.workingDays = workingDays; self.hoursPerDay = hoursPerDay; self.workersPerDay = workersPerDay
        self.contractValue = contractValue; self.manualProgress = manualProgress; self.depositRequiredToStart = depositRequiredToStart
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.deletedAt = deletedAt
    }

    public func validate() throws {
        if name.isBlank || address.line.isBlank { throw DomainError.emptyName }
        if jobType == .other, (customJobType ?? "").isBlank { throw DomainError.customJobTypeRequired }
        if contractValue.isNegative { throw DomainError.negativeAmount }
        if let p = manualProgress, !(0...100).contains(p) { throw DomainError.invalidProgress }
        if let s = startDate, let e = estimatedCompletionDate, e < s { throw DomainError.completionBeforeStart }
        if scopeFields.contains(where: { $0.fieldKey.isBlank }) { throw DomainError.emptyFieldKey }
    }
}
