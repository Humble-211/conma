import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct DepositStep: View {
    @Bindable var viewModel: ProjectWizardViewModel
    @Environment(\.timeZone) private var timeZone
    @State private var usesPercentage = true

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            Card {
                Toggle(isOn: Binding(get: { viewModel.draft.deposit != nil }, set: { on in
                    viewModel.draft.deposit = on ? DraftDeposit(mode: .percentage((try? Percentage.input(20)) ?? Percentage.computed(20)), deadline: nil, requiredToStart: true) : nil
                })) { Text("wizard.deposit.required") }.tint(DSColor.accent).frame(minHeight: DSSpacing.minTouch).accessibilityIdentifier("wizard_deposit_toggle")
            }
            if let deposit = viewModel.draft.deposit {
                Card {
                    VStack(spacing: DSSpacing.md) {
                        Picker("wizard.deposit.mode", selection: $usesPercentage) {
                            Text("wizard.deposit.percentage").tag(true)
                            Text("wizard.deposit.fixed").tag(false)
                        }.pickerStyle(.segmented).accessibilityIdentifier("wizard_deposit_mode")
                        .onChange(of: usesPercentage) { _, pct in switchMode(toPercentage: pct) }
                        if usesPercentage {
                            FormRow("wizard.deposit.percentage") {
                                DecimalField("wizard.deposit.percentage", value: Binding(get: { percentagePoints }, set: { setPercentage($0) }), fractionDigits: 2).accessibilityIdentifier("wizard_deposit_value")
                            }
                        } else {
                            FormRow("wizard.deposit.fixed") {
                                MoneyField("wizard.deposit.fixed", amount: Binding(get: { fixedAmount }, set: { setFixed($0) }), currencyCode: viewModel.currency.rawValue).accessibilityIdentifier("wizard_deposit_value")
                            }
                        }
                        Divider()
                        FormRow("wizard.deposit.amount") {
                            MoneyText(amount: viewModel.preview.depositAmount?.amount ?? 0, currencyCode: viewModel.currency.rawValue, style: .headline)
                        }
                        Divider()
                        HStack {
                            Toggle(isOn: Binding(get: { deposit.deadline != nil }, set: { on in viewModel.draft.deposit?.deadline = on ? CalendarDate(Date(), timeZone: timeZone) : nil })) { Text("wizard.deposit.deadline") }.tint(DSColor.accent)
                            if let deadline = deposit.deadline {
                                DatePicker("", selection: Binding(get: { deadline.noonDate(in: timeZone) }, set: { viewModel.draft.deposit?.deadline = CalendarDate($0, timeZone: timeZone) }), displayedComponents: .date)
                                    .labelsHidden().accessibilityIdentifier("wizard_deposit_deadline")
                            }
                        }.frame(minHeight: DSSpacing.minTouch)
                        Divider()
                        Toggle(isOn: Binding(get: { deposit.requiredToStart }, set: { viewModel.draft.deposit?.requiredToStart = $0 })) { Text("wizard.deposit.blocksStart") }.tint(DSColor.accent).frame(minHeight: DSSpacing.minTouch)
                    }
                }
            }
        }
        .padding(.horizontal, DSSpacing.lg)
        .onAppear { if case .fixed? = viewModel.draft.deposit?.mode { usesPercentage = false } }
    }

    private var percentagePoints: Decimal? { if case .percentage(let p)? = viewModel.draft.deposit?.mode { return p.points } else { return nil } }
    private var fixedAmount: Decimal? { if case .fixed(let m)? = viewModel.draft.deposit?.mode { return m.amount } else { return nil } }

    private func setPercentage(_ points: Decimal?) {
        guard let points, let pct = try? Percentage.input(points) else { return }
        viewModel.draft.deposit?.mode = .percentage(pct)
    }
    private func setFixed(_ amount: Decimal?) { viewModel.draft.deposit?.mode = .fixed(Money(amount ?? 0, viewModel.currency)) }

    private func switchMode(toPercentage: Bool) {
        guard let contract = viewModel.draft.contractValue, let current = viewModel.preview.depositAmount else { return }
        if toPercentage {
            if let ratio = Percentage.ratio(current, over: contract), let pct = try? Percentage.input(min(max(ratio.points, 0), 100)) { viewModel.draft.deposit?.mode = .percentage(pct) }
        } else {
            viewModel.draft.deposit?.mode = .fixed(current)
        }
    }

}
