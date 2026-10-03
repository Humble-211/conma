import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct EstimateLineList: View {
    @Binding var lines: [DraftEstimateLine]
    let group: CostGroup
    let currency: CurrencyCode
    let showsRate: Bool            // labour detailed: rate/day × days
    let suggestions: [String]      // material chips
    let kindPicker: Bool           // other costs: OtherCostKind menu

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.sm) {
                        ForEach(suggestions, id: \.self) { label in
                            Button { add(label: label) } label: {
                                Text(verbatim: label).font(DSTypography.callout).padding(.horizontal, DSSpacing.md).padding(.vertical, DSSpacing.sm)
                                    .frame(minHeight: DSSpacing.minTouch)
                                    .background(DSColor.surface, in: Capsule()).overlay(Capsule().strokeBorder(DSColor.border))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, DSSpacing.lg)
                }
            }
            ForEach(Array(lines.enumerated()), id: \.element.id) { index, _ in
                Card { row(index) }.padding(.horizontal, DSSpacing.lg)
            }
            SecondaryButton("wizard.estimate.addLine", systemImage: "plus") { add(label: "") }
                .padding(.horizontal, DSSpacing.lg).accessibilityIdentifier("wizard_line_add")
            HStack {
                Text("wizard.estimate.total").font(DSTypography.headline)
                Spacer()
                MoneyText(amount: total.amount, currencyCode: currency.rawValue, style: .headline).accessibilityIdentifier("wizard_estimate_total")
            }.padding(.horizontal, DSSpacing.lg)
        }
    }

    private var total: Money { (try? Money.sum(lines.map(\.amount), currency: currency)) ?? .zero(currency) }

    @ViewBuilder private func row(_ index: Int) -> some View {
        VStack(spacing: DSSpacing.sm) {
            HStack {
                if kindPicker {
                    Picker("wizard.estimate.kind", selection: Binding(get: { lines[index].otherKind ?? .other }, set: { lines[index].otherKind = $0; lines[index].costGroup = $0.costGroup })) {
                        ForEach(OtherCostKind.allCases, id: \.self) { Text($0.titleKey).tag($0) }
                    }.labelsHidden()
                } else {
                    TextField(showsRate ? "wizard.estimate.worker" : "wizard.estimate.label", text: $lines[index].label).frame(minHeight: DSSpacing.minTouch)
                        .accessibilityIdentifier("wizard_line_label_\(index)")
                }
                Spacer()
                Button(role: .destructive) { lines.remove(at: index) } label: { Image(systemName: "trash") }.accessibilityLabel(Text("wizard.scope.remove"))
            }
            if showsRate {
                HStack(spacing: DSSpacing.md) {
                    FormRow("wizard.estimate.rate") { MoneyField("wizard.estimate.rate", amount: rateBinding(index), currencyCode: currency.rawValue) }
                    FormRow("wizard.estimate.days") { DecimalField("wizard.estimate.days", value: $lines[index].quantity, fractionDigits: 1) }
                }
                FormRow("wizard.estimate.amount") { MoneyText(amount: lines[index].amount.amount, currencyCode: currency.rawValue) }
            } else {
                FormRow("wizard.estimate.amount") { MoneyField("wizard.estimate.amount", amount: amountBinding(index), currencyCode: currency.rawValue).accessibilityIdentifier("wizard_line_amount_\(index)") }
            }
        }
        .onChange(of: lines[index].quantity) { _, _ in recompute(index) }
    }

    private func rateBinding(_ index: Int) -> Binding<Decimal?> {
        Binding(get: { lines[index].unitRate?.amount }, set: { lines[index].unitRate = $0.map { Money($0, currency) }; recompute(index) })
    }
    private func amountBinding(_ index: Int) -> Binding<Decimal?> {
        Binding(get: { lines[index].amount.isZero ? nil : lines[index].amount.amount }, set: { lines[index].amount = Money($0 ?? 0, currency) })
    }
    private func recompute(_ index: Int) {
        guard lines.indices.contains(index), let rate = lines[index].unitRate, let qty = lines[index].quantity else { return }
        lines[index].amount = rate.multiplied(by: qty)
    }
    private func add(label: String) {
        lines.append(DraftEstimateLine(id: UUID(), label: label, amount: .zero(currency), quantity: showsRate ? 1 : nil, unitRate: nil, costGroup: kindPicker ? OtherCostKind.other.costGroup : group, otherKind: kindPicker ? .other : nil, sortOrder: lines.count))
    }
}
