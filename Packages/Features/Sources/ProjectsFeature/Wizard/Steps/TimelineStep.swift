import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct TimelineStep: View {
    @Bindable var viewModel: ProjectWizardViewModel
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            Card {
                VStack(spacing: DSSpacing.md) {
                    dateRow("wizard.timeline.start", date: $viewModel.draft.startDate, id: "wizard_start_date") // lint:allow-string
                    Divider()
                    dateRow("wizard.timeline.end", date: $viewModel.draft.estimatedCompletionDate, id: "wizard_end_date") // lint:allow-string
                    if !viewModel.canContinue {
                        Text("wizard.error.completionBeforeStart").font(DSTypography.caption).foregroundStyle(DSColor.danger)
                    }
                }
            }
            Card {
                VStack(spacing: DSSpacing.md) {
                    FormRow("wizard.timeline.workingDays") { IntegerField("wizard.timeline.workingDays", value: $viewModel.draft.workingDays) }
                    Divider()
                    FormRow("wizard.timeline.hoursPerDay") { DecimalField("wizard.timeline.hoursPerDay", value: $viewModel.draft.hoursPerDay, fractionDigits: 1) }
                    Divider()
                    FormRow("wizard.timeline.workersPerDay") { IntegerField("wizard.timeline.workersPerDay", value: $viewModel.draft.workersPerDay) }
                }
            }
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    private func dateRow(_ title: LocalizedStringKey, date: Binding<CalendarDate?>, id: String) -> some View {
        HStack {
            Toggle(isOn: Binding(get: { date.wrappedValue != nil }, set: { on in date.wrappedValue = on ? CalendarDate(Date(), timeZone: timeZone) : nil })) { Text(title) }
                .tint(DSColor.accent)
            if let current = date.wrappedValue {
                DatePicker("", selection: Binding(get: { current.noonDate(in: timeZone) }, set: { date.wrappedValue = CalendarDate($0, timeZone: timeZone) }), displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.compact)
                    .accessibilityIdentifier(id)
            }
        }
        .frame(minHeight: DSSpacing.minTouch)
    }
}
