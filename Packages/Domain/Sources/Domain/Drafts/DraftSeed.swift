import Foundation

public extension ProjectDraft {
    /// Spec 3.6: seed an edit sheet from persisted data. Ids are preserved so DraftDiff can match rows.
    init(project: Project, estimateLines: [ProjectEstimateLine], scheduleItems: [PaymentScheduleItem], step: Int) {
        self.init()
        jobType = project.jobType
        customJobType = project.customJobType
        customer = .existing(project.customerId)
        projectName = project.name
        address = project.address
        scopeDescription = project.scopeDescription
        scopeFields = project.scopeFields.sorted { $0.sortOrder < $1.sortOrder }.map { DraftScopeField(id: $0.id, key: $0.fieldKey, value: $0.valueText, sortOrder: $0.sortOrder) }
        startDate = project.startDate
        estimatedCompletionDate = project.estimatedCompletionDate
        workingDays = project.workingDays
        hoursPerDay = project.hoursPerDay
        workersPerDay = project.workersPerDay
        labourMode = .detailed
        func kind(_ g: CostGroup) -> OtherCostKind? {
            switch g {
            case .subcontractor: return .subcontractors
            case .equipment: return .equipmentRental
            case .permit: return .permits
            case .other: return .other
            case .labour, .material: return nil
            }
        }
        func toDraft(_ l: ProjectEstimateLine) -> DraftEstimateLine {
            DraftEstimateLine(id: l.id, label: l.label, amount: l.amount, quantity: l.quantity, unitRate: l.unitRate, costGroup: l.costGroup, otherKind: kind(l.costGroup), sortOrder: l.sortOrder)
        }
        let live = estimateLines.filter { !$0.isDeleted }.sorted { $0.sortOrder < $1.sortOrder }
        labourLines = live.filter { $0.costGroup == .labour }.map(toDraft)
        materialLines = live.filter { $0.costGroup == .material }.map(toDraft)
        otherLines = live.filter { ![.labour, .material].contains($0.costGroup) }.map(toDraft)
        contractValue = project.contractValue
        let items = scheduleItems.filter { !$0.isDeleted }.sorted { $0.sortOrder < $1.sortOrder }
        if let dep = items.first(where: \.isDeposit) {
            deposit = DraftDeposit(mode: .fixed(dep.amount), deadline: dep.dueDate, requiredToStart: project.depositRequiredToStart)
        }
        scheduleTemplate = .custom
        schedule = items.map { DraftScheduleRow(id: $0.id, label: $0.label, percentage: $0.percentage, amount: $0.amount, dueDate: $0.dueDate, trigger: $0.triggerText, isDeposit: $0.isDeposit) }
        self.step = step
        updatedAt = project.updatedAt
    }
}
