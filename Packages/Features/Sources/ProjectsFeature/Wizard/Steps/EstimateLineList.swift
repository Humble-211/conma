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
            ForEach($lines) { $line in
                Card { row($line) }.padding(.horizontal, DSSpacing.lg)
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

    @ViewBuilder private func row(_ line: Binding<DraftEstimateLine>) -> some View {
        let id = line.wrappedValue.id
        let index = lines.firstIndex(where: { $0.id == id }) ?? 0
        VStack(spacing: DSSpacing.sm) {
            HStack {
                if kindPicker {
                    Picker("wizard.estimate.kind", selection: Binding(get: { line.wrappedValue.otherKind ?? .other }, set: { kind in
                        line.wrappedValue.otherKind = kind; line.wrappedValue.costGroup = kind.costGroup; line.wrappedValue.label = kind.labelKeyString
                    })) {
                        ForEach(OtherCostKind.allCases, id: \.self) { Text($0.titleKey).tag($0) }
                    }.labelsHidden()
                } else {
                    TextField(showsRate ? "wizard.estimate.worker" : "wizard.estimate.label", text: line.label).frame(minHeight: DSSpacing.minTouch)
                        .accessibilityIdentifier("wizard_line_label_\(index)")
                }
                Spacer()
                Button(role: .destructive) { lines.removeAll { $0.id == id } } label: { Image(systemName: "trash") }
                    .accessibilityLabel(Text("wizard.scope.remove")).accessibilityIdentifier("wizard_line_delete_\(index)")
            }
            if showsRate {
                HStack(spacing: DSSpacing.md) {
                    FormRow("wizard.estimate.rate") { MoneyField("wizard.estimate.rate", amount: rateBinding(line), currencyCode: currency.rawValue) }
                    FormRow("wizard.estimate.days") { DecimalField("wizard.estimate.days", value: line.quantity, fractionDigits: 1) }
                }
                FormRow("wizard.estimate.amount") { MoneyText(amount: line.wrappedValue.amount.amount, currencyCode: currency.rawValue) }
            } else {
                FormRow("wizard.estimate.amount") { MoneyField("wizard.estimate.amount", amount: amountBinding(line), currencyCode: currency.rawValue).accessibilityIdentifier("wizard_line_amount_\(index)") }
            }
        }
        .onChange(of: line.wrappedValue.quantity) { _, _ in recompute(id) }
    }

    private func rateBinding(_ line: Binding<DraftEstimateLine>) -> Binding<Decimal?> {
        let id = line.wrappedValue.id
        return Binding(get: { line.wrappedValue.unitRate?.amount }, set: { rate in
            line.wrappedValue.unitRate = rate.map { Money($0, currency) }; recompute(id)
        })
    }
    private func amountBinding(_ line: Binding<DraftEstimateLine>) -> Binding<Decimal?> {
        Binding(get: { line.wrappedValue.amount.isZero ? nil : line.wrappedValue.amount.amount }, set: { line.wrappedValue.amount = Money($0 ?? 0, currency) })
    }
    private func recompute(_ id: UUID) {
        guard showsRate, let index = lines.firstIndex(where: { $0.id == id }) else { return }
        if let rate = lines[index].unitRate, let qty = lines[index].quantity {
            lines[index].amount = rate.multiplied(by: qty)
        } else {
            lines[index].amount = .zero(currency)
        }
    }
    private func add(label: String) {
        lines.append(DraftEstimateLine(id: UUID(), label: kindPicker ? OtherCostKind.other.labelKeyString : label, amount: .zero(currency), quantity: showsRate ? 1 : nil, unitRate: nil, costGroup: kindPicker ? OtherCostKind.other.costGroup : group, otherKind: kindPicker ? .other : nil, sortOrder: lines.count))
    }
}
