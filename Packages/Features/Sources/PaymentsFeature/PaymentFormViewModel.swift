import Foundation
import Observation
import SwiftUI
import Domain
import FeatureSupport

@Observable
@MainActor
public final class PaymentFormViewModel {
    public var draft: PaymentDraft
    public private(set) var snapshot: ProjectInsightsInputs.Snapshot?
    public private(set) var original: Payment?
    /// Stays true after a successful save/delete so a second tap during the dismissal cannot write again.
    public private(set) var isSaving = false
    public private(set) var showErrors = false
    /// The payment or its project could not be loaded: the form closes after the alert.
    public private(set) var loadFailed = false
    public var alertKey: LocalizedStringKey?

    public let request: PaymentFormRequest
    public let currency: CurrencyCode
    private let companyId: UUID
    private let paymentRepository: any PaymentRepository
    private let insightsRepository: any InsightsRepository
    private let actor: ActivityActor
    private let today: CalendarDate
    private var didApplyDefaults = false
    private var methodTouched = false
    private var itemTouched = false
    private var didFinish = false

    public init(request: PaymentFormRequest, companyId: UUID, currency: CurrencyCode, paymentRepository: any PaymentRepository,
                insightsRepository: any InsightsRepository, actor: ActivityActor, today: CalendarDate) {
        self.request = request; self.companyId = companyId; self.currency = currency
        self.paymentRepository = paymentRepository; self.insightsRepository = insightsRepository; self.actor = actor; self.today = today
        self.draft = PaymentDraft(paidOn: today, method: PaymentDraft.defaultMethod(lastUsed: nil))
    }

    public var isEditing: Bool { if case .edit = request { return true } else { return false } }
    /// Keyboard up only for "Record payment" without a stage (spec §2 "Lối vào payment").
    public var focusAmount: Bool {
        if case .create(_, let item) = request { return item == nil }
        return false
    }
    private var projectId: UUID? {
        if case .create(let id, _) = request { return id }
        return original?.projectId
    }

    /// Bind to `.task`: loads the edited payment once, remembers the last method, then keeps the project live.
    public func start() async {
        if case .edit(let id) = request, original == nil {
            guard !loadFailed else { return }
            do {
                guard let payment = try await paymentRepository.get(id: id) else { loadFailed = true; alertKey = "payment.error.gone"; return }
                original = payment
                draft = PaymentDraft(editing: payment)
            } catch is CancellationError {
                return
            } catch { loadFailed = true; alertKey = "payment.error.load"; return }
        }
        if !isEditing, !didApplyDefaults {
            let last = try? await paymentRepository.lastUsedMethod(companyId: companyId)
            if !methodTouched { draft.method = PaymentDraft.defaultMethod(lastUsed: last ?? nil) }
        }
        guard let projectId else { return }
        do {
            for try await value in insightsRepository.observeProject(id: projectId) {
                guard let value else {
                    snapshot = nil
                    if !didFinish { loadFailed = true; alertKey = "payment.error.gone" }
                    return
                }
                snapshot = value
                applyDefaultsOnce()
            }
        } catch is CancellationError {
        } catch { loadFailed = true; alertKey = "payment.error.load" }
    }

    /// First snapshot only: the stage and amount implied by the entry point.
    private func applyDefaultsOnce() {
        guard !didApplyDefaults else { return }
        didApplyDefaults = true
        guard case .create(_, let itemId) = request else { return }
        if let itemId {
            guard let option = options.first(where: { $0.id == itemId }) else { return }   // stage deleted meanwhile: stays unlinked
            if !itemTouched { draft.scheduleItemId = itemId }
            if draft.amount == nil, option.remaining.amount > 0 { draft.amount = option.remaining.amount }
        } else if !itemTouched {
            draft.scheduleItemId = PaymentFormContext.defaultItemId(options)
        }
    }

    // MARK: Derived

    public var projectName: String? { snapshot?.project.name }
    public var options: [PaymentItemOption] {
        guard let snapshot else { return [] }
        return PaymentFormContext.options(items: snapshot.scheduleItems, payments: snapshot.payments, excluding: original?.id, today: today, currency: currency)
    }
    public var selectedOption: PaymentItemOption? { draft.scheduleItemId.flatMap { id in options.first { $0.id == id } } }
    public var outstanding: Money? {
        snapshot.flatMap { PaymentFormContext.outstanding(project: $0.project, payments: $0.payments, excluding: original?.id) }
    }
    public var suggestions: [PaymentSuggestion] { PaymentFormContext.suggestions(option: selectedOption, outstanding: outstanding) }
    public var overpayment: Money? { PaymentFormContext.overpayment(amount: draft.amount, option: selectedOption) }
    public var errors: [PaymentDraftError] { draft.errors }
    public var canSubmit: Bool { !isSaving && snapshot != nil && !(isEditing && original == nil) }

    // MARK: Input

    public func selectMethod(_ method: PaymentMethod) { methodTouched = true; draft.method = method }
    public func selectItem(_ id: UUID?) { itemTouched = true; draft.scheduleItemId = id }
    public func apply(_ suggestion: PaymentSuggestion) { draft.amount = suggestion.money.amount }

    // MARK: Writes

    public func save() async -> Bool {
        guard !(isEditing && original == nil), !didFinish else { return false }
        showErrors = true
        guard draft.canSave, !isSaving, let projectId = snapshot?.project.id else { return false }
        isSaving = true
        do {
            if let original {
                try await paymentRepository.update(try draft.apply(to: original, now: Date()), actor: actor)
            } else {
                try await paymentRepository.create(try draft.makePayment(id: UUID(), companyId: companyId, projectId: projectId, currency: currency, now: Date()), actor: actor)
            }
            didFinish = true
            return true
        } catch {
            isSaving = false
            alertKey = Self.key(for: error)
            return false
        }
    }

    public func delete() async -> Bool {
        guard let original, !isSaving, !didFinish else { return false }
        isSaving = true
        do {
            try await paymentRepository.softDelete(id: original.id, actor: actor)
            didFinish = true
            return true
        } catch {
            isSaving = false
            alertKey = Self.key(for: error)
            return false
        }
    }

    static func key(for error: Error) -> LocalizedStringKey {
        switch error as? DomainError {
        case .notFound?: return "payment.error.gone"
        case .currencyMismatch?: return "error.currencyMismatch"
        case .incompletePayment?, .invalidPaymentAmount?: return "payment.error.incomplete"
        default: return "payment.error.saveFailed"
        }
    }
}
