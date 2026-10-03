import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct ScheduleStep: View {
    @Bindable var viewModel: ProjectWizardViewModel
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.sm) {
                    ForEach(PaymentScheduleTemplate.allCases, id: \.self) { template in
                        let selected = viewModel.draft.scheduleTemplate == template
                        Button { viewModel.applyTemplate(template) } label: {
                            Text(template.titleKey).font(DSTypography.callout.weight(.medium)).padding(.horizontal, DSSpacing.md).padding(.vertical, DSSpacing.sm)
                                .frame(minHeight: DSSpacing.minTouch)
                                .background(selected ? DSColor.accent : DSColor.surface, in: Capsule())
                                .foregroundStyle(selected ? DSColor.onAccent : DSColor.textPrimary)
                                .overlay(Capsule().strokeBorder(DSColor.border, lineWidth: selected ? 0 : 1))
                        }.buttonStyle(.plain).accessibilityIdentifier("wizard_template_" + template.rawValue)
                    }
                }.padding(.horizontal, DSSpacing.lg)
            }
            ForEach(Array(viewModel.draft.schedule.enumerated()), id: \.element.id) { index, row in
                Card { rowView(index, row) }.padding(.horizontal, DSSpacing.lg)
            }
            SecondaryButton("wizard.schedule.addRow", systemImage: "plus") {
                viewModel.draft.schedule.append(DraftScheduleRow(id: UUID(), label: "", percentage: nil, amount: nil, dueDate: nil, trigger: nil, isDeposit: viewModel.draft.schedule.isEmpty))
                if viewModel.draft.scheduleTemplate == nil { viewModel.draft.scheduleTemplate = .custom }
            }.padding(.horizontal, DSSpacing.lg).accessibilityIdentifier("wizard_schedule_add")
            Card {
                VStack(spacing: DSSpacing.sm) {
                    FormRow("wizard.schedule.total") { MoneyText(amount: viewModel.preview.scheduleTotal.amount, currencyCode: viewModel.currency.rawValue, style: .headline).accessibilityIdentifier("wizard_schedule_total") }
                    if let warning = viewModel.preview.scheduleWarning {
                        switch warning {
                        case .totalMismatch(let diff):
                            HStack(spacing: DSSpacing.xs) {
                                Text("wizard.schedule.mismatch").font(DSTypography.caption)
                                MoneyText(amount: diff.amount, currencyCode: viewModel.currency.rawValue, style: .caption)
                            }.foregroundStyle(DSColor.warning)
                        case .currencyMismatch:
                            Text("wizard.schedule.currencyMismatch").font(DSTypography.caption).foregroundStyle(DSColor.danger)
                        case .contractZero:
                            Text("wizard.schedule.noContract").font(DSTypography.caption).foregroundStyle(DSColor.warning)
                        }
                    }
                }
            }.padding(.horizontal, DSSpacing.lg)
        }
    }

    @ViewBuilder private func rowView(_ index: Int, _ row: DraftScheduleRow) -> some View {
        VStack(spacing: DSSpacing.sm) {
            HStack {
                if row.label.hasPrefix("schedule.row.") { // lint:allow-string
                    RowLabel.text(row.label).font(DSTypography.headline)
                } else {
                    TextField("wizard.schedule.label", text: $viewModel.draft.schedule[index].label).font(DSTypography.headline)
                }
                Spacer()
                if row.isDeposit { StatusBadge("schedule.row.deposit", tone: .warning) }
                Button(role: .destructive) { viewModel.draft.schedule.remove(at: index); viewModel.scheduleEdited(.none) } label: { Image(systemName: "trash") }.accessibilityLabel(Text("wizard.scope.remove"))
            }
            HStack(spacing: DSSpacing.md) {
                FormRow("wizard.schedule.percent") {
                    DecimalField("wizard.schedule.percent", value: Binding(get: { row.percentage?.points }, set: { pts in
                        if let pts {
                            guard let pct = try? Percentage.input(pts) else { return }
                            viewModel.draft.schedule[index].percentage = pct
                        } else {
                            viewModel.draft.schedule[index].percentage = nil
                        }
                        viewModel.scheduleEdited(.percentage(index))
                    }), fractionDigits: 2).accessibilityIdentifier("wizard_schedule_row_\(index)_pct")
                }
                FormRow("wizard.estimate.amount") {
                    MoneyField("wizard.estimate.amount", amount: Binding(get: { row.amount?.amount }, set: { amt in
                        viewModel.draft.schedule[index].amount = amt.map { Money($0, viewModel.currency) }
                        viewModel.scheduleEdited(.amount(index))
                    }), currencyCode: viewModel.currency.rawValue).accessibilityIdentifier("wizard_schedule_row_\(index)_amount")
                }
            }
            HStack {
                Toggle(isOn: Binding(get: { row.dueDate != nil }, set: { on in viewModel.draft.schedule[index].dueDate = on ? CalendarDate(Date(), timeZone: timeZone) : nil })) { Text("wizard.schedule.dueDate") }.tint(DSColor.accent)
                if let due = row.dueDate {
                    DatePicker("", selection: Binding(get: { due.noonDate(in: timeZone) }, set: { viewModel.draft.schedule[index].dueDate = CalendarDate($0, timeZone: timeZone) }), displayedComponents: .date).labelsHidden()
                }
            }.frame(minHeight: DSSpacing.minTouch)
            TextField("wizard.schedule.trigger", text: Binding(get: { row.trigger ?? "" }, set: { viewModel.draft.schedule[index].trigger = $0.isEmpty ? nil : $0 })).frame(minHeight: DSSpacing.minTouch)
        }
    }

}
