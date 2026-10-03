import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// Start / completion dates, days left or late, expected vs actual progress; "Add timeline" when no dates are set.
struct TimelineSection: View {
    let insights: ProjectInsights?
    let project: Project
    let today: CalendarDate
    let onEdit: () -> Void
    let onAdd: () -> Void
    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale

    var body: some View {
        let tl = insights?.timeline ?? TimelineInsight.make(start: project.startDate, completion: project.estimatedCompletionDate, today: today)
        let progress = insights?.progress ?? ProgressCalculator.percent(tasks: [], manualProgress: project.manualProgress)
        let hasDates = tl.startDate != nil || tl.estimatedCompletionDate != nil
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Text("detail.timeline.title").font(DSTypography.headline); Spacer()
                    Button("wizard.review.edit", action: onEdit).font(DSTypography.callout).accessibilityIdentifier("detail_edit_timeline")
                }
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    if hasDates {
                        FormRow("detail.timeline.start") { date(tl.startDate) }
                        FormRow("detail.timeline.completion") { date(tl.estimatedCompletionDate) }
                        if let r = tl.daysRemaining {
                            Text(Self.remainingKey(r))
                                .font(DSTypography.callout)
                                .foregroundStyle(r < 0 ? DSColor.danger : DSColor.textPrimary)
                        }
                        if tl.startDate == today {
                            Text("detail.timeline.startsToday").font(DSTypography.callout).foregroundStyle(DSColor.info)
                        }
                        DualProgressBar(expected: tl.expectedProgress, actual: progress, expectedLabel: "detail.timeline.expected", actualLabel: "detail.timeline.actual")
                    } else {
                        Text("detail.empty").foregroundStyle(DSColor.textSecondary)
                    }
                    if let d = project.workingDays { FormRow("wizard.timeline.workingDays") { Text(verbatim: "\(d)") } }
                    if let h = project.hoursPerDay { FormRow("wizard.timeline.hoursPerDay") { Text(verbatim: LocaleNumberParser.string(h, locale: locale, fractionDigits: 1)) } }
                    if let w = project.workersPerDay { FormRow("wizard.timeline.workersPerDay") { Text(verbatim: "\(w)") } }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("detail_timeline")
                if !hasDates {
                    SecondaryButton("detail.timeline.add", systemImage: "calendar.badge.plus", action: onAdd)
                        .accessibilityIdentifier("detail_add_timeline")
                }
            }
        }
    }

    private static func remainingKey(_ days: Int) -> LocalizedStringKey {
        if days > 0 { return "detail.timeline.daysLeft \(days)" }
        if days == 0 { return "detail.timeline.endsToday" }
        return "detail.timeline.daysLate \(-days)"
    }

    @ViewBuilder private func date(_ value: CalendarDate?) -> some View {
        if let value { DateLabel(value.noonDate(in: timeZone)) } else { Text(verbatim: "—") }
    }
}
