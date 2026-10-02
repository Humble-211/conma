import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct HomeView: View {
    private let viewModel: HomeViewModel

    public init(viewModel: HomeViewModel) { self.viewModel = viewModel }

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
                            ProjectCardView(summary: summary, progress: viewModel.progress(for: summary))
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
        .task { await viewModel.start() }
    }
}
