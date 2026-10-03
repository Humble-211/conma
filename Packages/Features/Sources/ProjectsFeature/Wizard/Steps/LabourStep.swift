import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct LabourStep: View {
    @Bindable var viewModel: ProjectWizardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            Picker("wizard.labour.mode", selection: $viewModel.draft.labourMode) {
                Text("wizard.labour.quick").tag(LabourEntryMode.quick)
                Text("wizard.labour.detailed").tag(LabourEntryMode.detailed)
            }
            .pickerStyle(.segmented).padding(.horizontal, DSSpacing.lg).accessibilityIdentifier("wizard_labour_mode")

            switch viewModel.draft.labourMode {
            case .quick:
                Card {
                    VStack(spacing: DSSpacing.md) {
                        FormRow("wizard.labour.workers") { IntegerField("wizard.labour.workers", value: quick.workers).accessibilityIdentifier("wizard_labour_workers") }
                        Divider()
                        FormRow("wizard.labour.rate") { MoneyField("wizard.labour.rate", amount: Binding(get: { quick.wrappedValue.dailyRate?.amount }, set: { quick.wrappedValue.dailyRate = $0.map { Money($0, viewModel.currency) } }), currencyCode: viewModel.currency.rawValue).accessibilityIdentifier("wizard_labour_rate") }
                        Divider()
                        FormRow("wizard.labour.days") { DecimalField("wizard.labour.days", value: quick.days, fractionDigits: 1).accessibilityIdentifier("wizard_labour_days") }
                        Divider()
                        FormRow("wizard.estimate.total") { MoneyText(amount: viewModel.preview.estimateByGroup[.labour]?.amount ?? 0, currencyCode: viewModel.currency.rawValue, style: .headline) }
                    }
                }.padding(.horizontal, DSSpacing.lg)
            case .detailed:
                EstimateLineList(lines: $viewModel.draft.labourLines, group: .labour, currency: viewModel.currency, showsRate: true, suggestions: [], kindPicker: false)
            }
        }
    }

    private var quick: Binding<LabourQuickInput> {
        Binding(get: { viewModel.draft.labourQuick ?? LabourQuickInput(workers: nil, dailyRate: nil, days: nil) }, set: { viewModel.draft.labourQuick = $0 })
    }
}
