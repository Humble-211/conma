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

    public init(labourRepository: any LabourRepository, projectId: UUID) { self.repository = labourRepository; self.projectId = projectId }

    public func start() async {
        do {
            for try await value in repository.observeProject(id: projectId) {
                list = value.map { LabourListComposer.compose(entries: $0.entries, employees: $0.employees, currency: $0.currency) }
            }
        } catch is CancellationError {
        } catch { errorKey = "labour.error.load" }
    }
}
