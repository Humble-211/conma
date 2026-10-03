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
                    ForEach(viewModel.timelineErrors.filter { $0 == .completionBeforeStart }, id: \.self) { errorText($0) }
                }
            }
            Card {
                VStack(spacing: DSSpacing.md) {
                    FormRow("wizard.timeline.workingDays") { IntegerField("wizard.timeline.workingDays", value: $viewModel.draft.workingDays).accessibilityIdentifier("wizard_working_days") }
                    Divider()
                    FormRow("wizard.timeline.hoursPerDay") { DecimalField("wizard.timeline.hoursPerDay", value: $viewModel.draft.hoursPerDay, fractionDigits: 1).accessibilityIdentifier("wizard_hours_per_day") }
                    Divider()
                    FormRow("wizard.timeline.workersPerDay") { IntegerField("wizard.timeline.workersPerDay", value: $viewModel.draft.workersPerDay).accessibilityIdentifier("wizard_workers_per_day") }
                    ForEach(viewModel.timelineErrors.filter { $0 != .completionBeforeStart }, id: \.self) { errorText($0) }
                }
            }
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    private func errorText(_ error: TimelineError) -> some View {
        let name = Self.name(error)
        return Text(LocalizedStringKey("timeline.error." + name))
            .font(DSTypography.caption).foregroundStyle(DSColor.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("timeline_error_" + name)
    }

    private static func name(_ error: TimelineError) -> String {
        switch error {
        case .completionBeforeStart: "completionBeforeStart" // lint:allow-string
        case .hoursPerDayOutOfRange: "hoursPerDayOutOfRange" // lint:allow-string
        case .workingDaysNegative: "workingDaysNegative" // lint:allow-string
        case .workersPerDayNegative: "workersPerDayNegative" // lint:allow-string
        }
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
