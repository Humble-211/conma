import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

private struct WizardItem: Identifiable { let id = UUID(); let draft: ProjectDraft }

public struct ProjectsListView: View {
    @Bindable private var viewModel: ProjectsListViewModel
    private let makeWizard: (ProjectDraft, @escaping (UUID) -> Void, @escaping () -> Void) -> AnyView
    private let makeDetail: (UUID) -> AnyView
    @State private var wizardDraft: WizardItem?
    @State private var path: [ProjectRoute] = []

    public init(viewModel: ProjectsListViewModel,
                makeWizard: @escaping (ProjectDraft, @escaping (UUID) -> Void, @escaping () -> Void) -> AnyView,
                makeDetail: @escaping (UUID) -> AnyView) {
        self.viewModel = viewModel; self.makeWizard = makeWizard; self.makeDetail = makeDetail
    }

    public var body: some View {
        NavigationStack(path: $path) {
            Group {
                if viewModel.isLoaded && viewModel.summaries.isEmpty {
                    VStack(spacing: DSSpacing.lg) {
                        if let draft = viewModel.draft {
                            DraftBanner(draft: draft, onContinue: { wizardDraft = WizardItem(draft: draft) }, onDiscard: { viewModel.discardDraft() }).padding(.horizontal, DSSpacing.lg)
                        } else {
                            EmptyState(systemImage: "folder", title: "projects.empty.title", message: "projects.empty.message")
                        }
                        PrimaryButton("projects.createFirst", systemImage: "plus") { wizardDraft = WizardItem(draft: ProjectDraft()) }.padding(.horizontal, DSSpacing.lg)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: DSSpacing.md) {
                            if let draft = viewModel.draft {
                                DraftBanner(draft: draft, onContinue: { wizardDraft = WizardItem(draft: draft) }, onDiscard: { viewModel.discardDraft() }).padding(.horizontal, DSSpacing.lg)
                            }
                            Picker("projects.filter", selection: $viewModel.filter) {
                                ForEach(PhaseFilter.allCases, id: \.self) { Text($0.titleKey).tag($0) }
                            }.pickerStyle(.segmented).padding(.horizontal, DSSpacing.lg).accessibilityIdentifier("projects_filter")
                            ForEach(viewModel.visible) { summary in
                                NavigationLink(value: ProjectRoute.detail(summary.project.id)) {
                                    ProjectCardView(summary: summary, progress: ProgressCalculator.percent(tasks: [], manualProgress: summary.project.manualProgress))
                                }.buttonStyle(.plain).padding(.horizontal, DSSpacing.lg)
                            }
                            if viewModel.visible.isEmpty && !viewModel.summaries.isEmpty {
                                Text("projects.noMatches").font(DSTypography.callout).foregroundStyle(DSColor.textSecondary).padding(.horizontal, DSSpacing.lg)
                            }
                        }.padding(.vertical, DSSpacing.lg)
                    }
                    .accessibilityIdentifier("projects_list")
                }
            }
            .background(DSColor.background)
            .navigationTitle("projects.title")
            .searchable(text: $viewModel.query, prompt: Text("projects.search"))
            .overlay(alignment: .bottomTrailing) {
                FloatingActionButton(accessibilityLabel: "projects.add") { wizardDraft = WizardItem(draft: ProjectDraft()) }
                    .padding(DSSpacing.xl).accessibilityIdentifier("projects_add")
            }
            .navigationDestination(for: ProjectRoute.self) { route in
                switch route { case .detail(let id): makeDetail(id) }
            }
        }
        .fullScreenCover(item: $wizardDraft) { item in
            makeWizard(item.draft, { id in wizardDraft = nil; viewModel.reloadDraft(); path = [.detail(id)] }, { wizardDraft = nil; viewModel.reloadDraft() })
        }
        .task { await viewModel.start() }
    }
}
