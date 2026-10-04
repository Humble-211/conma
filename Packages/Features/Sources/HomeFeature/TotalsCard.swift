import SwiftUI
import Domain
import DesignSystem

struct TotalsCard: View {
    let totals: CompanyTotals
    @Environment(\.locale) private var locale

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text("home.totals.title").font(DSTypography.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DSSpacing.sm) {
                    SummaryTile("home.totals.active", value: Text(verbatim: "\(totals.activeJobs)"))
                        .accessibilityElement(children: .combine).accessibilityIdentifier("home_total_active")
                    SummaryTile("home.totals.outstanding", value: money(totals.outstanding))
                        .accessibilityElement(children: .combine).accessibilityIdentifier("home_total_outstanding")
                    SummaryTile("home.totals.collected", value: money(totals.collected))
                        .accessibilityElement(children: .combine).accessibilityIdentifier("home_total_collected")
                    SummaryTile("home.totals.spent", value: money(totals.spent))
                        .accessibilityElement(children: .combine).accessibilityIdentifier("home_total_spent")
                    SummaryTile("home.totals.cash", value: money(totals.cashPosition), tone: totals.cashPosition.isNegative ? .danger : .neutral)
                        .accessibilityElement(children: .combine).accessibilityIdentifier("home_total_cash")
                }
                if totals.excludedCount > 0 {
                    Text("home.totals.excluded \(totals.excludedCount)").font(DSTypography.caption).foregroundStyle(DSColor.warning)
                }
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("home_totals")
    }

    private func money(_ m: Money) -> Text {
        Text(verbatim: MoneyFormat.string(m.amount, currencyCode: m.currency.rawValue, locale: locale))
    }
}
