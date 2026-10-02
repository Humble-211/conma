import Foundation
import Observation
import SwiftUI
import Domain

@Observable
@MainActor
public final class HomeViewModel {
    public private(set) var summaries: [ProjectSummary] = []
    public private(set) var errorKey: LocalizedStringKey?
    public private(set) var isLoaded = false

    private let projectRepository: any ProjectRepository
    private let companyId: UUID

    public init(projectRepository: any ProjectRepository, companyId: UUID) {
        self.projectRepository = projectRepository; self.companyId = companyId
    }

    /// Runs until cancelled (bind to the view's `.task`).
    public func start() async {
        do {
            for try await value in projectRepository.observeSummaries(companyId: companyId) {
                summaries = value
                isLoaded = true
            }
        } catch is CancellationError {
        } catch {
            errorKey = "home.error"
        }
    }

    public func progress(for summary: ProjectSummary) -> Int {
        ProgressCalculator.percent(tasks: [], manualProgress: summary.project.manualProgress)
    }
}
