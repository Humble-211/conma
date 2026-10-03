import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// Hosts one wizard step as an edit sheet. The wizard VM is created by the detail VM and owned here.
struct EditSectionSheet: View {
    let section: EditSection
    @State private var wizard: ProjectWizardViewModel
    let onSave: (ProjectWizardViewModel) async -> Bool
    let onCancel: () -> Void
    @State private var saving = false
    @State private var saveFailed = false

    init(section: EditSection, wizard: ProjectWizardViewModel, onSave: @escaping (ProjectWizardViewModel) async -> Bool, onCancel: @escaping () -> Void) {
        self.section = section; _wizard = State(initialValue: wizard); self.onSave = onSave; self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            ScrollView { stepBody.padding(.vertical, DSSpacing.lg) }
                .scrollDismissesKeyboard(.interactively)
                .background(DSColor.background)
                .navigationTitle(section.wizardStep.titleKey)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("sheet.cancel", action: onCancel).accessibilityIdentifier("sheet_cancel") }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("sheet.save") { Task { saving = true; let ok = await onSave(wizard); if !ok { saveFailed = true }; saving = false } }
                            .disabled(saving || !wizard.canContinue).accessibilityIdentifier("sheet_save")
                    }
                }
                .alert("detail.saveFailed", isPresented: $saveFailed) { Button("sheet.ok") {} }
        }
    }

    @ViewBuilder private var stepBody: some View {
        switch section {
        case .scope: ScopeStep(viewModel: wizard)
        case .timeline: TimelineStep(viewModel: wizard)
        case .estimate(let g):
            switch g {
            case .labour: LabourStep(viewModel: wizard)
            case .material: MaterialStep(viewModel: wizard)
            default: OtherCostsStep(viewModel: wizard)
            }
        case .priceDeposit:
            VStack(spacing: DSSpacing.lg) { PriceStep(viewModel: wizard); DepositStep(viewModel: wizard) }
        case .schedule: ScheduleStep(viewModel: wizard)
        }
    }
}
