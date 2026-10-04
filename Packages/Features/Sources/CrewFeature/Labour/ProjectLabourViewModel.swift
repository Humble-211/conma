import Foundation
import Observation
import SwiftUI
import Domain

@Observable
@MainActor
public final class ProjectLabourViewModel {
    public private(set) var list: ProjectLabourList?
    public private(set) var errorKey: LocalizedStringKey?
    public let projectId: UUID
    private let repository: any LabourRepository
    private var generation = 0

    public init(labourRepository: any LabourRepository, projectId: UUID) { self.repository = labourRepository; self.projectId = projectId }

    /// Bind to `.task(id:)`; a retry starts a new generation.
    public func start() async {
        generation += 1
        let g = generation
        errorKey = nil
        do {
            for try await value in repository.observeProject(id: projectId) {
                guard g == generation else { return }
                list = value.map { LabourListComposer.compose(entries: $0.entries, employees: $0.employees, currency: $0.currency) }
            }
        } catch is CancellationError {
        } catch { if g == generation { errorKey = "labour.error.load" } }
    }

    public func retry() { errorKey = nil }
}
