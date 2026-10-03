import Foundation
import Observation
import SwiftUI
import Domain
import FeatureSupport

@Observable
@MainActor
public final class ProjectsListViewModel {
    public private(set) var summaries: [ProjectSummary] = []
    public private(set) var isLoaded = false
    public var filter: PhaseFilter
    public var query = ""
    public private(set) var draft: ProjectDraft?
    public var errorKey: LocalizedStringKey?

    private let projectRepository: any ProjectRepository
    private let draftStore: any DraftStore
    public let companyId: UUID
    private var defaultFilterApplied = false

    public init(projectRepository: any ProjectRepository, draftStore: any DraftStore, companyId: UUID) {
        self.projectRepository = projectRepository; self.draftStore = draftStore; self.companyId = companyId
        self.filter = .all
        reloadDraft()
    }

    public func start() async {
        do {
            for try await value in projectRepository.observeSummaries(companyId: companyId) {
                summaries = value
                if !defaultFilterApplied {
                    defaultFilterApplied = true
                    filter = value.contains { $0.project.status.phase == .inWork } ? .inWork : .all
                }
                isLoaded = true
            }
        } catch is CancellationError {
        } catch { errorKey = "home.error" }
    }

    public var visible: [ProjectSummary] {
        let q = SearchFold.normalize(query)
        return summaries.filter { s in
            filter.matches(s.project.status) && (q.isEmpty || [s.project.name, s.project.address.line, s.project.address.city ?? "", s.customerName].contains { SearchFold.normalize($0).contains(q) })
        }
    }

    /// Applies a persisted filter (scene storage) before the first load picks the default.
    public func restoreFilter(_ value: PhaseFilter) { filter = value; defaultFilterApplied = true }

    public func reloadDraft() { draft = (try? draftStore.load()) ?? nil }
    public func discardDraft() { try? draftStore.clear(); draft = nil }
}
