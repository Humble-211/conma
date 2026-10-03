import Foundation
import Observation
import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

@Observable
@MainActor
public final class ActivityListViewModel {
    public private(set) var entries: [ActivityLogEntry] = []
    public private(set) var isLoaded = false
    public private(set) var failed = false

    public let projectId: UUID
    public let currency: CurrencyCode
    private let activityLogRepository: any ActivityLogRepository

    public init(projectId: UUID, currency: CurrencyCode, activityLogRepository: any ActivityLogRepository) {
        self.projectId = projectId; self.currency = currency; self.activityLogRepository = activityLogRepository
    }

    /// Full history, newest first.
    public func load() async {
        do { entries = try await activityLogRepository.list(projectId: projectId); failed = false }
        catch { failed = true }
        isLoaded = true
    }
}

public struct ActivityListView: View {
    private let viewModel: ActivityListViewModel

    public init(viewModel: ActivityListViewModel) { self.viewModel = viewModel }

    public var body: some View {
        Group {
            if !viewModel.isLoaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.failed {
                EmptyState(systemImage: "exclamationmark.triangle", title: "error.generic", message: "detail.error")
            } else if viewModel.entries.isEmpty {
                EmptyState(systemImage: "clock", title: "detail.activity.title", message: "activity.empty")
                    .accessibilityIdentifier("activity_empty")
            } else {
                List(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                    ActivityEntryRow(entry: entry, currency: viewModel.currency)
                        .accessibilityIdentifier("activity_list_row_\(index)")
                }
                .listStyle(.plain)
                .accessibilityIdentifier("activity_list")
            }
        }
        .background(DSColor.background)
        .navigationTitle("detail.activity.title")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }
}
