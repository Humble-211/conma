import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct HomeView: View {
    private let viewModel: HomeViewModel

    private let makeDetail: (UUID) -> AnyView

    public init(viewModel: HomeViewModel, makeDetail: @escaping (UUID) -> AnyView) {
        self.viewModel = viewModel; self.makeDetail = makeDetail
    }

    public var body: some View {
        Group {
            if let errorKey = viewModel.errorKey {
                EmptyState(systemImage: "exclamationmark.triangle", title: "home.error", message: errorKey)
            } else if viewModel.isLoaded && viewModel.summaries.isEmpty {
                EmptyState(systemImage: "hammer", title: "home.empty.title", message: "home.empty.message")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DSSpacing.md) {
                        SectionHeader("home.ongoingJobs")
                        ForEach(viewModel.summaries) { summary in
                            NavigationLink(value: ProjectRoute.detail(summary.project.id)) {
                                ProjectCardView(summary: summary, progress: viewModel.progress(for: summary))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, DSSpacing.lg)
                        }
                    }
                    .padding(.vertical, DSSpacing.lg)
                }
                .accessibilityIdentifier("home_list")
            }
        }
        .background(DSColor.background)
        .navigationTitle("home.title")
        .navigationDestination(for: ProjectRoute.self) { route in
            switch route { case .detail(let id): makeDetail(id) }
        }
        .task { await viewModel.start() }
    }
}
