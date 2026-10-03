import Foundation
import Observation
import SwiftUI
import Domain

@Observable
@MainActor
public final class HomeViewModel {
    public private(set) var dashboard: Dashboard?
    public private(set) var isLoaded = false
    public private(set) var errorKey: LocalizedStringKey?
    public var currency: String { dashboard?.totals.currency.rawValue ?? "" }

    private var snapshot: DashboardInputs.Snapshot?
    private var today: CalendarDate
    private let insightsRepository: any InsightsRepository
    private let companyId: UUID
    private var generation = 0

    public init(insightsRepository: any InsightsRepository, companyId: UUID, today: CalendarDate) {
        self.insightsRepository = insightsRepository; self.companyId = companyId; self.today = today
    }

    /// Runs until cancelled (bind to the view's `.task`).
    public func start() async {
        generation += 1
        let g = generation
        errorKey = nil
        do {
            for try await value in insightsRepository.observeDashboard(companyId: companyId) {
                guard g == generation else { return }
                snapshot = value
                isLoaded = true
                recompose()
            }
        } catch is CancellationError {
        } catch {
            errorKey = "home.error"
        }
    }

    public func update(today: CalendarDate) {
        guard today != self.today else { return }
        self.today = today
        recompose()
    }

    /// Clears the error; the view then calls `start()` again in a fresh task.
    public func retry() { errorKey = nil; isLoaded = false }

    private func recompose() {
        if let snapshot { dashboard = DashboardComposer.compose(snapshot.with(today: today)) }
    }
}
