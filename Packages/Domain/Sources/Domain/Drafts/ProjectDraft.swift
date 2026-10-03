import Foundation

public struct NewCustomerInput: Codable, Equatable, Sendable {
    public var name: String
    public var phone: String?
    public var email: String?
    public var preferredContact: ContactMethod?
    public var companyName: String?
    public var secondaryContact: String?
    public var notes: String?

    public init(name: String, phone: String?, email: String?, preferredContact: ContactMethod?, companyName: String?, secondaryContact: String?, notes: String?) {
        self.name = name; self.phone = phone; self.email = email; self.preferredContact = preferredContact
        self.companyName = companyName; self.secondaryContact = secondaryContact; self.notes = notes
    }
}

public enum CustomerChoice: Codable, Equatable, Sendable {
    case existing(UUID)
    case new(NewCustomerInput)
}

public enum LabourEntryMode: String, Codable, Equatable, Sendable { case quick, detailed }

public struct LabourQuickInput: Codable, Equatable, Sendable {
    public var workers: Int?
    public var dailyRate: Money?
    public var days: Decimal?
    public init(workers: Int?, dailyRate: Money?, days: Decimal?) { self.workers = workers; self.dailyRate = dailyRate; self.days = days }
}

public struct DraftEstimateLine: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var label: String
    public var amount: Money
    public var quantity: Decimal?
    public var unitRate: Money?
    public var costGroup: CostGroup
    public var otherKind: OtherCostKind?
    public var sortOrder: Int

    public init(id: UUID, label: String, amount: Money, quantity: Decimal?, unitRate: Money?, costGroup: CostGroup, otherKind: OtherCostKind?, sortOrder: Int) {
        self.id = id; self.label = label; self.amount = amount; self.quantity = quantity; self.unitRate = unitRate
        self.costGroup = costGroup; self.otherKind = otherKind; self.sortOrder = sortOrder
    }
}

public struct DraftScopeField: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var key: String
    public var value: String
    public var sortOrder: Int
    public init(id: UUID, key: String, value: String, sortOrder: Int) { self.id = id; self.key = key; self.value = value; self.sortOrder = sortOrder }
}

public enum DepositMode: Codable, Equatable, Sendable {
    case percentage(Percentage)
    case fixed(Money)
}

public struct DraftDeposit: Codable, Equatable, Sendable {
    public var mode: DepositMode
    public var deadline: CalendarDate?
    public var requiredToStart: Bool
    public init(mode: DepositMode, deadline: CalendarDate?, requiredToStart: Bool) { self.mode = mode; self.deadline = deadline; self.requiredToStart = requiredToStart }
}

public struct DraftScheduleRow: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var label: String
    public var percentage: Percentage?
    public var amount: Money?
    public var dueDate: CalendarDate?
    public var trigger: String?
    public var isDeposit: Bool

    public init(id: UUID, label: String, percentage: Percentage?, amount: Money?, dueDate: CalendarDate?, trigger: String?, isDeposit: Bool) {
        self.id = id; self.label = label; self.percentage = percentage; self.amount = amount; self.dueDate = dueDate; self.trigger = trigger; self.isDeposit = isDeposit
    }
}

public enum PaymentScheduleTemplate: String, Codable, Equatable, Sendable, CaseIterable {
    case depositFinal, depositProgressFinal, fourStage, custom
}

public enum DraftField: String, Codable, Sendable, Hashable { case jobType, customJobType, customer, addressLine, contractValue }

public enum DraftError: Error, Equatable, Sendable {
    case missing(Set<DraftField>)
    case negativeAmount
    case completionBeforeStart
    case invalidTimeline([TimelineError])
    case currencyMismatch
}

/// Wizard state, draft file and edit-sheet input in one value (spec 3.1).
public struct ProjectDraft: Codable, Equatable, Sendable {
    public var jobType: JobType?
    public var customJobType: String?
    public var customer: CustomerChoice?
    public var projectName: String?
    public var address: Address?
    public var scopeDescription: String?
    public var scopeFields: [DraftScopeField] = []
    public var startDate: CalendarDate?
    public var estimatedCompletionDate: CalendarDate?
    public var workingDays: Int?
    public var hoursPerDay: Decimal?
    public var workersPerDay: Int?
    public var labourMode: LabourEntryMode = .quick
    public var labourQuick: LabourQuickInput?
    public var labourLines: [DraftEstimateLine] = []
    public var materialLines: [DraftEstimateLine] = []
    public var otherLines: [DraftEstimateLine] = []
    public var contractValue: Money?
    public var deposit: DraftDeposit?
    public var scheduleTemplate: PaymentScheduleTemplate?
    public var schedule: [DraftScheduleRow] = []
    public var step: Int = 1
    /// Epoch by default; the persistence layer stamps it on save.
    public var updatedAt: Date = Date(timeIntervalSince1970: 0)

    public init() {}

    /// Tolerant decoding: a draft written before a field existed still loads (missing keys take
    /// the declared defaults). Encoding stays synthesized.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        jobType = try c.decodeIfPresent(JobType.self, forKey: .jobType)
        customJobType = try c.decodeIfPresent(String.self, forKey: .customJobType)
        customer = try c.decodeIfPresent(CustomerChoice.self, forKey: .customer)
        projectName = try c.decodeIfPresent(String.self, forKey: .projectName)
        address = try c.decodeIfPresent(Address.self, forKey: .address)
        scopeDescription = try c.decodeIfPresent(String.self, forKey: .scopeDescription)
        scopeFields = try c.decodeIfPresent([DraftScopeField].self, forKey: .scopeFields) ?? []
        startDate = try c.decodeIfPresent(CalendarDate.self, forKey: .startDate)
        estimatedCompletionDate = try c.decodeIfPresent(CalendarDate.self, forKey: .estimatedCompletionDate)
        workingDays = try c.decodeIfPresent(Int.self, forKey: .workingDays)
        hoursPerDay = try c.decodeIfPresent(Decimal.self, forKey: .hoursPerDay)
        workersPerDay = try c.decodeIfPresent(Int.self, forKey: .workersPerDay)
        labourMode = try c.decodeIfPresent(LabourEntryMode.self, forKey: .labourMode) ?? .quick
        labourQuick = try c.decodeIfPresent(LabourQuickInput.self, forKey: .labourQuick)
        labourLines = try c.decodeIfPresent([DraftEstimateLine].self, forKey: .labourLines) ?? []
        materialLines = try c.decodeIfPresent([DraftEstimateLine].self, forKey: .materialLines) ?? []
        otherLines = try c.decodeIfPresent([DraftEstimateLine].self, forKey: .otherLines) ?? []
        contractValue = try c.decodeIfPresent(Money.self, forKey: .contractValue)
        deposit = try c.decodeIfPresent(DraftDeposit.self, forKey: .deposit)
        scheduleTemplate = try c.decodeIfPresent(PaymentScheduleTemplate.self, forKey: .scheduleTemplate)
        schedule = try c.decodeIfPresent([DraftScheduleRow].self, forKey: .schedule) ?? []
        step = try c.decodeIfPresent(Int.self, forKey: .step) ?? 1
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
    }

    /// True when nothing user-entered is present (step/updatedAt/labourMode are not content).
    public var isEmpty: Bool {
        jobType == nil && Self.blank(customJobType) && customerIsBlank && projectName == nil && addressIsBlank && scopeDescription == nil
            && scopeFields.isEmpty && startDate == nil && estimatedCompletionDate == nil && workingDays == nil && hoursPerDay == nil
            && workersPerDay == nil && labourQuick == nil && labourLines.isEmpty && materialLines.isEmpty && otherLines.isEmpty
            && contractValue == nil && deposit == nil && scheduleTemplate == nil && schedule.isEmpty
    }

    private static func blank(_ s: String?) -> Bool {
        s == nil || s?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
    }

    private var addressIsBlank: Bool {
        guard let a = address else { return true }
        return Self.blank(a.line) && Self.blank(a.unit) && Self.blank(a.city) && Self.blank(a.region) && Self.blank(a.postalCode)
    }

    private var customerIsBlank: Bool {
        switch customer {
        case nil: return true
        case .existing?: return false
        case .new(let i)?:
            return Self.blank(i.name) && Self.blank(i.phone) && Self.blank(i.email) && i.preferredContact == nil
                && Self.blank(i.companyName) && Self.blank(i.secondaryContact) && Self.blank(i.notes)
        }
    }
}
