import Foundation

public enum BundleWarning: Equatable, Sendable, Hashable {
    case scheduleTotalMismatch(difference: Money)
    case depositExceedsContract
    case scheduleEmpty
}

public struct NewProjectBundle: Equatable, Sendable {
    public let project: Project
    public let scopeFields: [ProjectScopeField]
    public let estimateLines: [ProjectEstimateLine]
    public let scheduleItems: [PaymentScheduleItem]
    public let newCustomer: Customer?
    public let warnings: [BundleWarning]

    public init(project: Project, scopeFields: [ProjectScopeField], estimateLines: [ProjectEstimateLine], scheduleItems: [PaymentScheduleItem], newCustomer: Customer?, warnings: [BundleWarning]) {
        self.project = project; self.scopeFields = scopeFields; self.estimateLines = estimateLines; self.scheduleItems = scheduleItems; self.newCustomer = newCustomer; self.warnings = warnings
    }
}

public extension JobType {
    /// Default project name (user data from then on, never re-localized).
    var englishName: String {
        switch self {
        case .generalRenovation: return "General Renovation"
        case .basementRenovation: return "Basement Renovation"
        case .kitchen: return "Kitchen"
        case .bathroom: return "Bathroom"
        case .landscaping: return "Landscaping"
        case .roofing: return "Roofing"
        case .plumbing: return "Plumbing"
        case .electrical: return "Electrical"
        case .hvac: return "HVAC"
        case .flooring: return "Flooring"
        case .painting: return "Painting"
        case .drywall: return "Drywall"
        case .concrete: return "Concrete"
        case .deckFence: return "Deck / Fence"
        case .framing: return "Framing"
        case .windowsDoors: return "Windows / Doors"
        case .exterior: return "Exterior"
        case .demolition: return "Demolition"
        case .commercial: return "Commercial"
        case .other: return "Other"
        }
    }
}

public enum ProjectDraftAssembler {
    public static func defaultName(for draft: ProjectDraft) -> String? {
        if let name = draft.projectName, !name.isBlank { return name.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let type = draft.jobType else { return nil }
        if type == .other { return draft.customJobType.flatMap { $0.isBlank ? nil : $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
        return type.englishName
    }

    /// Spec 3.5.
    public static func assemble(_ draft: ProjectDraft, companyId: UUID, currency: CurrencyCode, now: Date) throws -> NewProjectBundle {
        var missing = Set<DraftField>()
        if draft.jobType == nil { missing.insert(.jobType) }
        if draft.jobType == .other, (draft.customJobType ?? "").isBlank { missing.insert(.customJobType) }
        switch draft.customer {
        case nil: missing.insert(.customer)
        case .new(let input)? where input.name.isBlank: missing.insert(.customer)
        default: break
        }
        if (draft.address?.line ?? "").isBlank { missing.insert(.addressLine) }
        if draft.contractValue == nil { missing.insert(.contractValue) }
        if !missing.isEmpty { throw DraftError.missing(missing) }

        guard let jobType = draft.jobType, let address = draft.address, let contract = draft.contractValue, let name = defaultName(for: draft) else {
            throw DraftError.missing([.jobType])
        }
        let allMoney: [Money] = [contract] + draft.allEstimateLines(currency: currency).map(\.amount)
            + draft.schedule.compactMap(\.amount) + [draft.deposit].compactMap { dep -> Money? in
                if case .fixed(let m)? = dep?.mode { return m } else { return nil }
            }
        if allMoney.contains(where: { $0.currency != currency }) { throw DraftError.currencyMismatch }
        if allMoney.contains(where: \.isNegative) { throw DraftError.negativeAmount }
        if let s = draft.startDate, let e = draft.estimatedCompletionDate, e < s { throw DraftError.completionBeforeStart }
        if let w = draft.workingDays, w < 0 { throw DraftError.invalidTimeline }
        if let w = draft.workersPerDay, w < 0 { throw DraftError.invalidTimeline }
        if let h = draft.hoursPerDay, !(h > 0 && h <= 24) { throw DraftError.invalidTimeline }

        let projectId = UUID()
        var newCustomer: Customer?
        let customerId: UUID
        switch draft.customer {
        case .existing(let id)?: customerId = id
        case .new(let input)?:
            let customer = Customer(id: UUID(), companyId: companyId, name: input.name.trimmingCharacters(in: .whitespacesAndNewlines), phone: input.phone, email: input.email,
                                    preferredContact: input.preferredContact, companyName: input.companyName, secondaryContact: input.secondaryContact, notes: input.notes,
                                    createdAt: now, updatedAt: now, deletedAt: nil)
            newCustomer = customer; customerId = customer.id
        case nil: throw DraftError.missing([.customer])
        }

        let scopeFields = draft.scopeFields
            .filter { !$0.key.isBlank && !$0.value.isBlank }
            .sorted { $0.sortOrder < $1.sortOrder }
            .enumerated()
            .map { index, f in ProjectScopeField(id: f.id, companyId: companyId, projectId: projectId, fieldKey: f.key, valueText: f.value.trimmingCharacters(in: .whitespacesAndNewlines), sortOrder: index, createdAt: now, updatedAt: now, deletedAt: nil) }

        var sortByGroup: [CostGroup: Int] = [:]
        let estimateLines = draft.allEstimateLines(currency: currency).map { line -> ProjectEstimateLine in
            let order = sortByGroup[line.costGroup, default: 0]; sortByGroup[line.costGroup] = order + 1
            return ProjectEstimateLine(id: line.id, companyId: companyId, projectId: projectId, costGroup: line.costGroup, label: line.label, amount: line.amount,
                                       quantity: line.quantity, unitRate: line.unitRate, sortOrder: order, createdAt: now, updatedAt: now, deletedAt: nil)
        }

        var warnings: [BundleWarning] = []
        var rows = ScheduleMath.recompute(rows: draft.schedule, contract: contract, edited: .none).rows
        if rows.isEmpty, let dep = draft.deposit {
            let amount: Money
            switch dep.mode {
            case .fixed(let m): amount = m
            case .percentage(let p): amount = contract.multiplied(by: p)
            }
            rows = [DraftScheduleRow(id: UUID(), label: "schedule.row.deposit", percentage: nil, amount: amount, dueDate: dep.deadline, trigger: nil, isDeposit: true)]
        }
        let scheduleItems = rows.filter { $0.amount != nil }.enumerated().compactMap { index, row -> PaymentScheduleItem? in
            guard let amount = row.amount else { return nil }
            let due = row.dueDate ?? (row.isDeposit ? draft.deposit?.deadline : nil)
            return PaymentScheduleItem(id: row.id, companyId: companyId, projectId: projectId, label: row.label, amount: amount, percentage: row.percentage, dueDate: due,
                                       triggerText: row.trigger, isDeposit: row.isDeposit, notes: nil, sortOrder: index, createdAt: now, updatedAt: now, deletedAt: nil)
        }
        if scheduleItems.isEmpty {
            warnings.append(.scheduleEmpty)
        } else {
            let total = try Money.sum(scheduleItems.map(\.amount), currency: currency)
            if total != contract { warnings.append(.scheduleTotalMismatch(difference: try total.subtracting(contract))) }
        }
        if let dep = draft.deposit {
            let depositAmount: Money
            switch dep.mode {
            case .fixed(let m): depositAmount = m
            case .percentage(let p): depositAmount = contract.multiplied(by: p)
            }
            if depositAmount.amount > contract.amount { warnings.append(.depositExceedsContract) }
        }

        let project = Project(id: projectId, companyId: companyId, customerId: customerId, name: name, jobType: jobType,
                              customJobType: jobType == .other ? draft.customJobType?.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                              status: .estimate, address: address, scopeDescription: draft.scopeDescription, scopeFields: scopeFields,
                              startDate: draft.startDate, estimatedCompletionDate: draft.estimatedCompletionDate, workingDays: draft.workingDays,
                              hoursPerDay: draft.hoursPerDay, workersPerDay: draft.workersPerDay, contractValue: contract, manualProgress: nil,
                              depositRequiredToStart: draft.deposit?.requiredToStart ?? false, createdAt: now, updatedAt: now, deletedAt: nil)
        try project.validate()
        try newCustomer?.validate()
        return NewProjectBundle(project: project, scopeFields: scopeFields, estimateLines: estimateLines, scheduleItems: scheduleItems, newCustomer: newCustomer, warnings: warnings)
    }
}
