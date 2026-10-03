import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct ProjectWizardView: View {
    @Bindable private var viewModel: ProjectWizardViewModel
    private let customerRepository: any CustomerRepository
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale

    public init(viewModel: ProjectWizardViewModel, customerRepository: any CustomerRepository) {
        self.viewModel = viewModel; self.customerRepository = customerRepository
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                StepHeader(title: viewModel.step.titleKey, step: viewModel.step.rawValue, total: WizardStep.total)
                    .padding(.top, DSSpacing.sm)
                ScrollView {
                    stepBody.padding(.vertical, DSSpacing.lg)
                }
                .scrollDismissesKeyboard(.interactively)
                if let errorKey = viewModel.errorKey {
                    Text(errorKey).font(DSTypography.callout).foregroundStyle(DSColor.danger).padding(.horizontal, DSSpacing.lg)
                }
                StepFooter(canContinue: viewModel.canContinue, canSkip: viewModel.canSkip, isLast: viewModel.step == .review,
                           onContinue: { if viewModel.step == .review { Task { await viewModel.create() } } else { viewModel.next() } },
                           onSkip: { viewModel.skip() })
            }
            .background(DSColor.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.step.previous != nil {
                        Button { viewModel.back() } label: { Label("wizard.back", systemImage: "chevron.left") }.accessibilityIdentifier("wizard_back")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { viewModel.requestClose() } label: { Image(systemName: "xmark") }.accessibilityIdentifier("wizard_close")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("wizard.done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("wizard.close.title", isPresented: $viewModel.showCloseDialog, titleVisibility: .visible) {
                Button("wizard.close.saveDraft") { viewModel.saveDraftAndClose() }
                Button("wizard.close.discard", role: .destructive) { viewModel.discardDraftAndClose() }
                Button("wizard.close.cancel", role: .cancel) {}
            }
            .confirmationDialog("wizard.jobType.change.title", isPresented: Binding(get: { viewModel.pendingJobTypeChange != nil }, set: { if !$0 { viewModel.pendingJobTypeChange = nil } }), titleVisibility: .visible) {
                Button("wizard.jobType.change.keep") { viewModel.confirmJobTypeChange(keepFields: true, labelFor: { ScopeFieldCatalog.labelString(forFieldKey: $0, locale: locale) }) }
                Button("wizard.jobType.change.clear", role: .destructive) { viewModel.confirmJobTypeChange(keepFields: false, labelFor: { $0 }) }
                Button("wizard.close.cancel", role: .cancel) { viewModel.pendingJobTypeChange = nil }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .background { viewModel.flushAutosave() } }
        }
        .interactiveDismissDisabled(true)
    }

    @ViewBuilder private var stepBody: some View {
        switch viewModel.step {
        case .jobType: JobTypeStep(viewModel: viewModel)
        case .customer: CustomerStep(viewModel: viewModel, customerRepository: customerRepository)
        case .location: LocationStep(viewModel: viewModel)
        case .scope: ScopeStep(viewModel: viewModel)
        case .timeline: TimelineStep(viewModel: viewModel)
        case .labour: LabourStep(viewModel: viewModel)
        case .material: MaterialStep(viewModel: viewModel)
        case .otherCosts: OtherCostsStep(viewModel: viewModel)
        case .price: PriceStep(viewModel: viewModel)
        case .deposit: DepositStep(viewModel: viewModel)
        case .schedule: ScheduleStep(viewModel: viewModel)
        case .review: ReviewStep(viewModel: viewModel)
        }
    }
}
