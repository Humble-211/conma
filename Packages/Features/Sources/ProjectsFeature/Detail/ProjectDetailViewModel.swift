import Foundation
import Observation
import SwiftUI
import Domain
import FeatureSupport

public enum EditSection: Hashable, Identifiable {
    case scope, timeline, estimate(CostGroup), priceDeposit, schedule
    public var id: String { String(describing: self) }
    var wizardStep: WizardStep {
        switch self {
        case .scope: return .scope
        case .timeline: return .timeline
        case .estimate(let g): return g == .labour ? .labour : (g == .material ? .material : .otherCosts)
        case .priceDeposit: return .price
        case .schedule: return .schedule
        }
    }
}

/// A DraftStore that never persists: edit sheets must not touch the wizard draft file.
struct NullDraftStore: DraftStore {
    func load() throws -> ProjectDraft? { nil }
    func save(_ draft: ProjectDraft) throws {}
    func clear() throws {}
}

@Observable
@MainActor
public final class ProjectDetailViewModel {
    public private(set) var snapshot: ProjectDetailSnapshot?
    public private(set) var isLoaded = false
    public var errorKey: LocalizedStringKey?
    public var editing: EditSection?
    public private(set) var insights: ProjectInsights?
    public private(set) var activity: [ActivityLogEntry] = []
    /// Failure of a status/progress/customer/delete write; the view shows it as an alert.
    public var actionErrorKey: LocalizedStringKey?
    public private(set) var today: CalendarDate
    private var insightsSnapshot: ProjectInsightsInputs.Snapshot?

    public let projectId: UUID
    public let companyId: UUID
    public let currency: CurrencyCode
    private let projectRepository: any ProjectRepository
    private let estimateRepository: any ProjectEstimateRepository
    private let scheduleRepository: any PaymentScheduleRepository
    private let insightsRepository: any InsightsRepository
    private let activityLogRepository: any ActivityLogRepository
    public let customerRepository: any CustomerRepository
    private let actor: ActivityActor

    public init(projectId: UUID, companyId: UUID, currency: CurrencyCode, projectRepository: any ProjectRepository, estimateRepository: any ProjectEstimateRepository,
                scheduleRepository: any PaymentScheduleRepository, insightsRepository: any InsightsRepository, activityLogRepository: any ActivityLogRepository,
                customerRepository: any CustomerRepository, actor: ActivityActor, today: CalendarDate) {
        self.projectId = projectId; self.companyId = companyId; self.currency = currency
        self.projectRepository = projectRepository; self.estimateRepository = estimateRepository; self.scheduleRepository = scheduleRepository; self.actor = actor
        self.insightsRepository = insightsRepository; self.activityLogRepository = activityLogRepository; self.customerRepository = customerRepository
        self.today = today
    }

    public func start() async {
        do {
            for try await value in projectRepository.observeDetail(id: projectId) { snapshot = value; isLoaded = true }
        } catch is CancellationError {
        } catch { errorKey = "detail.error" }
    }

    /// Runs alongside `start()`; bind to a second `.task`.
    public func startInsights() async {
        do {
            for try await value in insightsRepository.observeProject(id: projectId) {
                insightsSnapshot = value
                insights = value.map { ProjectInsightsComposer.compose($0.with(today: today)) }
            }
        } catch is CancellationError {
        } catch { errorKey = "detail.error" }
    }

    /// Latest five entries for the Activity section.
    public func startActivity() async {
        do {
            for try await value in activityLogRepository.observeForProject(projectId: projectId, limit: 5) { activity = value }
        } catch {}
    }

    /// Recomposes insights for a new day without waiting for a database emission.
    public func update(today: CalendarDate) {
        guard today != self.today else { return }
        self.today = today
        insights = insightsSnapshot.map { ProjectInsightsComposer.compose($0.with(today: today)) }
    }

    /// Returns the outcome (for the "set progress to 100%" suggestion) or nil on failure.
    public func changeStatus(_ status: ProjectStatus) async -> StatusChangeOutcome? {
        guard let project = snapshot?.project else { return nil }
        let outcome = ProjectStatusChange.apply(project, to: status)
        do {
            try await projectRepository.changeStatus(id: projectId, to: status, actor: actor)
            return outcome
        } catch { actionErrorKey = Self.key(for: error); return nil }
    }

    public func setProgress(_ value: Int?) async -> Bool {
        do { try await projectRepository.setManualProgress(id: projectId, to: value, actor: actor); return true }
        catch { actionErrorKey = Self.key(for: error); return false }
    }

    public func changeCustomer(_ customerId: UUID) async -> Bool {
        do { try await projectRepository.changeCustomer(id: projectId, to: customerId, actor: actor); return true }
        catch { actionErrorKey = Self.key(for: error); return false }
    }

    public func deleteProject() async -> Bool {
        do { try await projectRepository.softDelete(id: projectId, actor: actor); return true }
        catch { actionErrorKey = Self.key(for: error); return false }
    }

    static func key(for error: Error) -> LocalizedStringKey {
        switch error as? DomainError {
        case .notFound?: return "error.projectGone"
        case .customerDeleted?: return "error.customerDeleted"
        case .currencyMismatch?: return "error.currencyMismatch"
        case .invalidProgress?: return "error.invalidProgress"
        default: return "error.generic"
        }
    }

    /// Wizard VM seeded from the current snapshot, parked on the section's step, with no autosave.
    /// The view sets `editing` after it has stored the returned VM, so the sheet never opens empty.
    public func makeEditWizard(_ section: EditSection) -> ProjectWizardViewModel? {
        guard let s = snapshot else { return nil }
        let draft = ProjectDraft(project: s.project, estimateLines: s.estimateLines, scheduleItems: s.scheduleItems, step: section.wizardStep.rawValue)
        return ProjectWizardViewModel(draft: draft, companyId: companyId, currency: currency, projectRepository: projectRepository, draftStore: NullDraftStore(),
                                      actor: actor, onCreated: { _ in }, onDismiss: {})
    }

    /// Persists only the edited section. Returns false on failure; the sheet surfaces the alert.
    public func save(_ wizard: ProjectWizardViewModel, section: EditSection) async -> Bool {
        guard let s = snapshot else { return false }
        let draft = wizard.draft
        let now = Date()
        do {
            switch section {
            case .scope:
                var project = s.project
                project.scopeDescription = draft.scopeDescription
                project.scopeFields = DraftDiff.scopeFields(old: s.project.scopeFields, new: draft.scopeFields, companyId: companyId, projectId: projectId, now: now)
                try await projectRepository.save(project, actor: actor)
            case .timeline:
                var project = s.project
                project.startDate = draft.startDate; project.estimatedCompletionDate = draft.estimatedCompletionDate
                project.workingDays = draft.workingDays; project.hoursPerDay = draft.hoursPerDay; project.workersPerDay = draft.workersPerDay
                try await projectRepository.save(project, actor: actor)
            case .estimate(let group):
                let lines: [DraftEstimateLine]
                switch group {
                case .labour: lines = draft.allEstimateLines(currency: currency).filter { $0.costGroup == .labour }
                case .material: lines = draft.materialLines
                default: lines = draft.otherLines
                }
                if group == .labour || group == .material {
                    let change = try DraftDiff.estimateLines(group: group, old: s.estimateLines, new: lines, companyId: companyId, projectId: projectId, currency: currency, now: now)
                    try await estimateRepository.replace(projectId: projectId, group: group, change: change, actor: actor)
                } else {
                    // "Other costs" span several cost groups: replace each group that appears in old or new.
                    let groups = Set(s.estimateLines.map(\.costGroup)).union(lines.map(\.costGroup)).subtracting([.labour, .material])
                    for g in groups {
                        let change = try DraftDiff.estimateLines(group: g, old: s.estimateLines, new: lines.filter { $0.costGroup == g }, companyId: companyId, projectId: projectId, currency: currency, now: now)
                        try await estimateRepository.replace(projectId: projectId, group: g, change: change, actor: actor)
                    }
                }
            case .priceDeposit:
                var project = s.project
                if let contract = draft.contractValue { project.contractValue = contract }
                project.depositRequiredToStart = draft.deposit?.requiredToStart ?? false
                try await projectRepository.save(project, actor: actor)
                // Deposit row: update/insert/delete the isDeposit item to match the draft deposit.
                var rows = draft.schedule
                if let dep = draft.deposit {
                    let amount: Money
                    switch dep.mode { case .fixed(let m): amount = m; case .percentage(let p): amount = project.contractValue.multiplied(by: p) }
                    if let i = rows.firstIndex(where: \.isDeposit) { rows[i].amount = amount; rows[i].percentage = nil; rows[i].dueDate = dep.deadline }
                    else { rows.insert(DraftScheduleRow(id: UUID(), label: "schedule.row.deposit", percentage: nil, amount: amount, dueDate: dep.deadline, trigger: nil, isDeposit: true), at: 0) }
                } else {
                    rows.removeAll(where: \.isDeposit)
                }
                let change = try DraftDiff.scheduleItems(old: s.scheduleItems, new: rows, contract: project.contractValue, companyId: companyId, projectId: projectId, now: now)
                try await scheduleRepository.replace(projectId: projectId, change: change, actor: actor)
            case .schedule:
                let change = try DraftDiff.scheduleItems(old: s.scheduleItems, new: draft.schedule, contract: s.project.contractValue, companyId: companyId, projectId: projectId, now: now)
                try await scheduleRepository.replace(projectId: projectId, change: change, actor: actor)
            }
            editing = nil
            return true
        } catch {
            return false
        }
    }
}
