import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct PriceStep: View {
    @Bindable var viewModel: ProjectWizardViewModel

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            Card {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Text("wizard.price.contract").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                    MoneyField("wizard.price.contract", amount: Binding(get: { viewModel.draft.contractValue?.amount }, set: { viewModel.draft.contractValue = $0.map { Money($0, viewModel.currency) } }), currencyCode: viewModel.currency.rawValue)
                        .accessibilityIdentifier("wizard_contract_value")
                }
            }
            let p = viewModel.preview
            let profitAmount: Decimal = p.projectedProfit?.amount ?? 0
            HStack(spacing: DSSpacing.md) {
                SummaryTile("wizard.price.estimatedCost", value: Text(p.estimatedCost.amount, format: .currency(code: viewModel.currency.rawValue)))
                SummaryTile("wizard.price.profit", value: Text(profitAmount, format: .currency(code: viewModel.currency.rawValue)),
                            tone: (p.projectedProfit?.isNegative ?? false) ? .danger : .success)
            }
            Card {
                FormRow("wizard.price.margin") {
                    if let margin = p.projectedMargin { Text(verbatim: "\(margin.points)%").font(DSTypography.money(.headline)) } else { Text(verbatim: "—") }
                }
            }
        }
        .padding(.horizontal, DSSpacing.lg)
    }
}
