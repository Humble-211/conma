import Foundation
import Observation
import SwiftUI
import Domain
import FeatureSupport

@Observable
@MainActor
public final class ProjectWizardViewModel {
    public var draft: ProjectDraft {
        didSet {
            guard draft != oldValue else { return }
            if draft.contractValue != oldValue.contractValue, !draft.schedule.isEmpty {
                draft.schedule = ScheduleMath.recompute(rows: draft.schedule, contract: draft.contractValue ?? .zero(currency), edited: .rescale).rows
            }
            if draft.deposit != oldValue.deposit, draft.schedule.contains(where: \.isDeposit) {
                let contract = draft.contractValue ?? .zero(currency)
                let applied = ScheduleMath.applyDeposit(rows: draft.schedule, contract: contract, deposit: draft.deposit)
                draft.schedule = ScheduleMath.recompute(rows: applied, contract: contract, edited: .none).rows
            }
            recomputePreview(); scheduleAutosave()
        }
    }
    public private(set) var step: WizardStep
    public var missing: Set<DraftField> = []
    public private(set) var preview: DraftFinancialPreview
    public private(set) var isSaving = false
    public var errorKey: LocalizedStringKey?
    public var showCloseDialog = false
    public var pendingJobTypeChange: JobType?

    public let companyId: UUID
    public let currency: CurrencyCode
    private let projectRepository: any ProjectRepository
    private let draftStore: any DraftStore
    private let actor: ActivityActor
    private let onCreated: (UUID) -> Void
    private let onDismiss: () -> Void
    private var autosaveTask: Task<Void, Never>?

    public init(draft: ProjectDraft, companyId: UUID, currency: CurrencyCode, projectRepository: any ProjectRepository, draftStore: any DraftStore,
                actor: ActivityActor, onCreated: @escaping (UUID) -> Void, onDismiss: @escaping () -> Void) {
        self.draft = draft
        self.step = WizardStep(rawValue: draft.step) ?? .jobType
        self.preview = DraftFinancialPreview.compute(draft, currency: currency)
        self.companyId = companyId; self.currency = currency
        self.projectRepository = projectRepository; self.draftStore = draftStore; self.actor = actor
        self.onCreated = onCreated; self.onDismiss = onDismiss
    }

    // MARK: Navigation

    public var canContinue: Bool {
        switch step {
        case .jobType: return draft.jobType != nil && (draft.jobType != .other || !(draft.customJobType ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
        case .customer:
            switch draft.customer {
            case .existing?: return true
            case .new(let input)?: return !input.name.trimmingCharacters(in: .whitespaces).isEmpty
            case nil: return false
            }
        case .location: return !(draft.address?.line ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        case .timeline:
            if let s = draft.startDate, let e = draft.estimatedCompletionDate { return e >= s }
            return true
        case .price: return draft.contractValue != nil
        default: return true
        }
    }

    public var canSkip: Bool { !step.isRequired && step != .review && (step != .timeline || canContinue) }

    /// Review Focus #3: keep foreign fields as custom:<label> or drop them.
    public func confirmJobTypeChange(keepFields: Bool, labelFor: (String) -> String) {
        guard let newType = pendingJobTypeChange else { return }
        let allowed = Set(ScopeFieldCatalog.fields(for: newType).map(\.key))
        if keepFields {
            draft.scopeFields = draft.scopeFields.map { field in
                guard !allowed.contains(field.key), !ScopeFieldCatalog.isCustom(field.key) else { return field }
                var copy = field; copy.key = ScopeFieldCatalog.customPrefix + labelFor(field.key); return copy
            }
        } else {
            draft.scopeFields.removeAll { !allowed.contains($0.key) && !ScopeFieldCatalog.isCustom($0.key) }
        }
        draft.jobType = newType
        if newType != .other { draft.customJobType = nil }
        pendingJobTypeChange = nil
    }

    public func next() { guard canContinue, let n = step.next else { return }; move(to: n) }
    public func skip() { guard canSkip, let n = step.next else { return }; move(to: n) }
    public func back() { guard let p = step.previous else { return }; move(to: p) }
    public func go(to target: WizardStep) { move(to: target) }

    private func move(to target: WizardStep) {
        step = target
        draft.step = target.rawValue
        persistNow()
    }

    // MARK: Close / drafts

    public func requestClose() {
        if draft.isEmpty { autosaveTask?.cancel(); onDismiss() } else { showCloseDialog = true }
    }

    public func saveDraftAndClose() { persistNow(); onDismiss() }

    public func discardDraftAndClose() {
        autosaveTask?.cancel()
        try? draftStore.clear()
        onDismiss()
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    public func flushAutosave() { autosaveTask?.cancel(); persistNow() }

    private func persistNow() {
        autosaveTask?.cancel()
        guard !draft.isEmpty else { return }
        var copy = draft
        copy.updatedAt = Date()
        try? draftStore.save(copy)
    }

    // MARK: Schedule helpers

    public func applyTemplate(_ template: PaymentScheduleTemplate) {
        draft.scheduleTemplate = template
        var depositPct: Percentage?
        if case .percentage(let p)? = draft.deposit?.mode { depositPct = p }
        let contract = draft.contractValue ?? .zero(currency)
        let rows = ScheduleMath.applyDeposit(rows: template.rows(depositPercentage: depositPct), contract: contract, deposit: draft.deposit)
        draft.schedule = ScheduleMath.recompute(rows: rows, contract: contract, edited: .none).rows
    }

    public func scheduleEdited(_ field: EditedField) {
        draft.schedule = ScheduleMath.recompute(rows: draft.schedule, contract: draft.contractValue ?? .zero(currency), edited: field).rows
    }

    private func recomputePreview() { preview = DraftFinancialPreview.compute(draft, currency: currency) }

    // MARK: Create

    public func create() async {
        guard !isSaving else { return }
        isSaving = true; errorKey = nil
        defer { isSaving = false }
        do {
            let bundle = try ProjectDraftAssembler.assemble(draft, companyId: companyId, currency: currency, now: Date())
            try await projectRepository.create(bundle, actor: actor)
            autosaveTask?.cancel()
            try? draftStore.clear()
            onCreated(bundle.project.id)
        } catch DraftError.missing(let fields) {
            missing = fields
            errorKey = "wizard.error.missing"
        } catch DraftError.completionBeforeStart {
            errorKey = "wizard.error.completionBeforeStart"
        } catch {
            errorKey = "wizard.error.saveFailed"
        }
    }
}
