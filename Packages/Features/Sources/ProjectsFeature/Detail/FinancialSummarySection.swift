import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// Contract → estimate (with the 2a per-group Edit buttons, always visible) → profit → spent (expandable by cost group)
/// → collected → outstanding → cash position → actual / projected-at-current profit.
struct FinancialSummarySection: View {
    let insights: ProjectInsights?
    let currency: CurrencyCode
    let onEditEstimate: (CostGroup) -> Void
    @State private var showSpentByGroup = false
    @Environment(\.locale) private var locale

    private static let groups: [CostGroup] = [.labour, .material, .subcontractor, .equipment, .permit, .other]
    private static let otherGroups: [CostGroup] = [.subcontractor, .equipment, .permit, .other]

    var body: some View {
        let f = insights?.financials
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text("detail.financials.title").font(DSTypography.headline)
                if insights != nil && f == nil {
                    Label("detail.financials.currencyMismatch", systemImage: "exclamationmark.triangle")
                        .font(DSTypography.caption).foregroundStyle(DSColor.warning)
                        .accessibilityIdentifier("detail_financials_mismatch")
                }
                row("detail.financials.contract", f?.adjustedContract)

                HStack {
                    Text("detail.financials.estimatedCost")
                    Spacer()
                    value(f?.estimatedCost, style: .headline).accessibilityIdentifier("detail_estimate_total")
                }
                estimateRow(Text(CostGroup.labour.titleKey), f?.estimateByGroup[.labour], identifier: "detail_edit_estimate_labour") { onEditEstimate(.labour) }
                estimateRow(Text(CostGroup.material.titleKey), f?.estimateByGroup[.material], identifier: "detail_edit_estimate_material") { onEditEstimate(.material) }
                estimateRow(Text("wizard.step.otherCosts"), f.map { otherEstimate($0) }, identifier: "detail_edit_estimate_other") { onEditEstimate(.other) }

                row("detail.financials.projectedProfit", f?.projectedProfit, margin: f?.projectedMargin)
                Divider()

                Button { withAnimation { showSpentByGroup.toggle() } } label: {
                    HStack {
                        Text("detail.financials.spent").foregroundStyle(DSColor.textPrimary)
                        Image(systemName: showSpentByGroup ? "chevron.up" : "chevron.down")
                            .font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                        Spacer()
                        value(f?.spentSoFar)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("detail_spent")
                if showSpentByGroup, let insights {
                    spentByGroup(insights)
                }

                row("detail.financials.collected", f?.collected)
                    .accessibilityElement(children: .combine).accessibilityIdentifier("detail_collected")
                row("detail.financials.outstanding", f?.outstandingBalance)
                    .accessibilityElement(children: .combine).accessibilityIdentifier("detail_outstanding")
                row("detail.financials.cash", f?.cashPosition, tone: (f?.cashPosition.isNegative ?? false) ? .danger : nil)
                    .accessibilityElement(children: .combine).accessibilityIdentifier("detail_cash")
                Divider()
                row(f?.profitLabel == .actual ? "detail.financials.actualProfit" : "detail.financials.projectedAtCurrent", f?.actualProfit, margin: f?.actualMargin,
                    tone: (f?.actualProfit.isNegative ?? false) ? .danger : nil)
                    .accessibilityElement(children: .combine).accessibilityIdentifier("detail_actual_profit")
                if let f, f.spentSoFar.amount == 0, f.collected.amount == 0 {
                    Text("detail.financials.empty").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail_financials")
    }

    @ViewBuilder private func spentByGroup(_ insights: ProjectInsights) -> some View {
        let f = insights.financials
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("detail.financials.byGroup").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
            ForEach(Self.groups, id: \.self) { group in
                let alert = insights.budgetAlerts.first { $0.group == group }
                HStack(alignment: .firstTextBaseline) {
                    Text(group.titleKey).font(DSTypography.callout)
                    if let alert {
                        StatusBadge(alert.level == .exceeded ? "budget.exceeded" : "budget.nearLimit", tone: alert.level == .exceeded ? .danger : .warning)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        value(f.map { $0.actualByGroup[group] ?? .zero(currency) }, style: .callout)
                        value(f?.estimateByGroup[group], style: .caption).foregroundStyle(DSColor.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("detail_spent_" + group.rawValue)
            }
        }
        .padding(.leading, DSSpacing.md)
    }

    private func estimateRow(_ title: Text, _ money: Money?, identifier: String, onEdit: @escaping () -> Void) -> some View {
        HStack {
            title.font(DSTypography.callout).foregroundStyle(DSColor.textSecondary)
            Spacer()
            value(money, style: .callout)
            Button("wizard.review.edit", action: onEdit).font(DSTypography.callout).accessibilityIdentifier(identifier)
        }
        .padding(.leading, DSSpacing.md)
    }

    private func row(_ title: LocalizedStringKey, _ money: Money?, margin: Percentage? = nil, tone: DSTone? = nil) -> some View {
        HStack {
            Text(title)
            Spacer()
            if money != nil, let margin {
                Text(verbatim: "(" + LocaleNumberParser.string(margin.points, locale: locale, fractionDigits: 1) + "%)")
                    .font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
            }
            value(money).foregroundStyle(tone?.foreground ?? DSColor.textPrimary)
        }
    }

    /// Amount, or an em dash when financials are unavailable (currency mismatch / not loaded yet).
    @ViewBuilder private func value(_ money: Money?, style: Font.TextStyle = .body) -> some View {
        if let money { MoneyText(amount: money.amount, currencyCode: currency.rawValue, style: style) }
        else { Text(verbatim: "—").font(DSTypography.money(style)) }
    }

    private func otherEstimate(_ f: ProjectFinancials) -> Money {
        let parts = Self.otherGroups.compactMap { f.estimateByGroup[$0] }
        return (try? Money.sum(parts, currency: currency)) ?? .zero(currency)
    }
}
