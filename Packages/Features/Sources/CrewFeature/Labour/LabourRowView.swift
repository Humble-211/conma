import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// Name, "8 days × $250.00", cost.
struct LabourRowView: View {
    let row: LabourRow
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: DSSpacing.md) {
            Image(systemName: "person.crop.circle").frame(width: 32, height: 32).foregroundStyle(DSColor.accent)
            VStack(alignment: .leading, spacing: 2) {
                name.font(DSTypography.callout).foregroundStyle(DSColor.textPrimary).lineLimit(1)
                Text("labour.row.detail \(LabourDays.text(row.entry.days, locale: locale)) \(money(row.entry.dailyRate))")
                    .font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
            }
            Spacer()
            MoneyText(amount: row.cost.amount, currencyCode: row.cost.currency.rawValue, style: .callout).foregroundStyle(DSColor.textPrimary)
        }
        .frame(minHeight: DSSpacing.minTouch)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var name: Text { row.employeeName.isEmpty ? Text("labour.unknownPerson") : Text(verbatim: row.employeeName) }
    private func money(_ m: Money) -> String { MoneyFormat.string(m.amount, currencyCode: m.currency.rawValue, locale: locale) }
}

/// Day headers (date + day total) and their rows; a row opens the edit form.
struct LabourDayList: View {
    let sections: [LabourDaySection]
    let onEdit: (UUID) -> Void
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        ForEach(sections) { section in
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                HStack {
                    DateLabel(section.day.noonDate(in: timeZone))
                    Spacer()
                    MoneyText(amount: section.total.amount, currencyCode: section.total.currency.rawValue, style: .caption)
                }
                .font(DSTypography.caption)
                .foregroundStyle(DSColor.textSecondary)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("detail_labour_day_" + section.day.storageString)
                ForEach(section.rows) { row in
                    Button { onEdit(row.id) } label: { LabourRowView(row: row) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("labour_row_" + row.id.uuidString)
                }
            }
        }
    }
}
