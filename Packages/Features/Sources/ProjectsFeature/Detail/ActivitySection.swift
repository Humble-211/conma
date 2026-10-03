import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// Latest activity entries on the detail screen plus a "See all" link to the full list.
struct ActivitySection<AllDestination: View>: View {
    let entries: [ActivityLogEntry]
    let currency: CurrencyCode
    @ViewBuilder let allDestination: () -> AllDestination
    @Environment(\.locale) private var locale

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Text("detail.activity.title").font(DSTypography.headline); Spacer()
                    NavigationLink { allDestination() } label: { Text("detail.activity.all").font(DSTypography.callout) }
                        .accessibilityIdentifier("detail_activity_all")
                }
                if entries.isEmpty {
                    Text("activity.empty").font(DSTypography.callout).foregroundStyle(DSColor.textSecondary)
                } else {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        ActivityEntryRow(entry: entry, currency: currency)
                            .accessibilityIdentifier("activity_row_\(index)")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail_activity")
    }
}

/// One activity entry: icon by action, localized description, relative time in the app locale.
struct ActivityEntryRow: View {
    let entry: ActivityLogEntry
    let currency: CurrencyCode
    @Environment(\.locale) private var locale

    var body: some View {
        ActivityRow(systemImage: entry.action.systemImage,
                    title: ActivityDescription.detail(for: entry).text(currency: currency.rawValue, locale: locale),
                    subtitle: Text(verbatim: Self.relative(entry.occurredAt, locale: locale)))
            .accessibilityElement(children: .combine)
    }

    static func relative(_ date: Date, locale: Locale, now: Date = Date()) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = locale
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: now)
    }
}
