import Foundation
import Observation
import SwiftUI
import Domain
import FeatureSupport

@Observable
@MainActor
public final class LabourFormViewModel {
    /// One selectable person (create: the live crew; edit: the entry's person, even after they left the crew).
    public struct PersonRow: Identifiable, Hashable {
        public let id: UUID
        public let name: String
        public let trade: String?
        public let dailyRate: Money?
    }

    public var draft: LabourDraft
    public private(set) var crew: [Employee] = []
    public private(set) var projectEntries: [LabourEntry] = []
    public private(set) var original: LabourEntry?
    public private(set) var originalPerson: Employee?
    public private(set) var isLoaded = false
    public private(set) var isSaving = false
    public private(set) var showErrors = false
    public private(set) var loadFailed = false
    public var alertKey: LocalizedStringKey?

    public let request: LabourFormRequest
    public let currency: CurrencyCode
    private let companyId: UUID
    private let labourRepository: any LabourRepository
    private let employeeRepository: any EmployeeRepository
    private let actor: ActivityActor
    private var createdCrew: [Employee] = []
    private var didFinish = false

    public init(request: LabourFormRequest, companyId: UUID, currency: CurrencyCode, labourRepository: any LabourRepository,
                employeeRepository: any EmployeeRepository, actor: ActivityActor, today: CalendarDate) {
        self.request = request; self.companyId = companyId; self.currency = currency
        self.labourRepository = labourRepository; self.employeeRepository = employeeRepository; self.actor = actor
        self.draft = LabourDraft(workDate: today)
    }

    public var isEditing: Bool { if case .edit = request { return true } else { return false } }
    private var projectId: UUID? {
        if case .create(let id) = request { return id }
        return original?.projectId
    }

    /// Bind to `.task`: edit loads the entry and its person once; create keeps the crew live.
    public func start() async {
        if case .edit(let id) = request {
            guard original == nil, !loadFailed else { return }
            do {
                guard let entry = try await labourRepository.get(id: id) else { loadFailed = true; alertKey = "labour.error.gone"; return }
                originalPerson = try await employeeRepository.get(id: entry.employeeId, includingDeleted: true)
                original = entry
                draft = LabourDraft(editing: entry)
                isLoaded = true
            } catch is CancellationError {
                return
            } catch { loadFailed = true; alertKey = "labour.error.load" }
            return
        }
        do {
            for try await value in employeeRepository.observeAll(companyId: companyId) { receiveCrew(value); isLoaded = true }
        } catch is CancellationError {
        } catch { alertKey = "labour.error.load" }
    }

    /// A new live-crew emission: people added in this sheet count as known once the crew contains them, and a selected
    /// person who has left the live crew is dropped from the draft (they can no longer be shown or saved).
    func receiveCrew(_ value: [Employee]) {
        crew = value
        let live = Set(value.map(\.id))
        createdCrew.removeAll { live.contains($0.id) }
        let selectable = live.union(createdCrew.map(\.id))
        draft.lines.removeAll { !selectable.contains($0.employeeId) }
    }

    /// Second `.task` (create only): this project's entries for the "already logged" notice. A failure only hides the notice.
    public func startEntries() async {
        guard case .create(let projectId) = request else { return }
        do {
            for try await value in labourRepository.observeProject(id: projectId) { projectEntries = value?.entries ?? [] }
        } catch {}
    }

    // MARK: Derived

    public var rows: [PersonRow] {
        if isEditing {
            guard let original else { return [] }
            return [PersonRow(id: original.employeeId, name: originalPerson?.name ?? "", trade: originalPerson?.trade, dailyRate: originalPerson?.dailyRate)]
        }
        let known = crew
        let all = CrewList.ordered(known + createdCrew.filter { c in !known.contains { $0.id == c.id } })
        return all.map { PersonRow(id: $0.id, name: $0.name, trade: $0.trade, dailyRate: $0.dailyRate) }
    }
    public func cost(for id: UUID) -> Money? { draft.cost(for: id, currency: currency) }
    public var total: Money? { draft.total(currency: currency) }
    public var errors: [LabourDraftError] { draft.errors }
    public func alreadyLogged(_ id: UUID) -> Decimal {
        isEditing ? 0 : LabourDraft.alreadyLoggedDays(employeeId: id, on: draft.workDate, entries: projectEntries, excluding: nil)
    }
    public var canSubmit: Bool { !isSaving && !(isEditing && original == nil) }

    // MARK: Input

    public func toggle(_ id: UUID) {
        guard !isEditing, let employee = (crew + createdCrew).first(where: { $0.id == id }) else { return }
        draft.toggle(employee)
    }

    /// "Add crew member" inside the sheet: creates the person and selects them.
    public func addPerson(_ employeeDraft: EmployeeDraft) async -> LocalizedStringKey? {
        do {
            let employee = try employeeDraft.makeEmployee(id: UUID(), companyId: companyId, currency: currency, now: Date())
            try await employeeRepository.create(employee)
            createdCrew.append(employee)
            draft.toggle(employee)
            return nil
        } catch { return CrewListViewModel.key(for: error) }
    }

    // MARK: Writes

    public func save() async -> Bool {
        guard !(isEditing && original == nil), !didFinish else { return false }
        showErrors = true
        guard draft.canSave, !isSaving, let projectId else { return false }
        isSaving = true
        do {
            if let original {
                try await labourRepository.update(try draft.apply(to: original, now: Date()), actor: actor)
            } else {
                try await labourRepository.create(try draft.makeEntries(companyId: companyId, projectId: projectId, currency: currency, now: Date()), actor: actor)
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
            try await labourRepository.softDelete(id: original.id, actor: actor)
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
        case .notFound?: return "labour.error.gone"
        case .incompleteLabour?, .invalidLabourDays?: return "labour.error.incomplete"
        case .currencyMismatch?: return "error.currencyMismatch"
        default: return "labour.error.saveFailed"
        }
    }
}
