import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct ProjectCardView: View {
    let summary: ProjectSummary
    let progress: Int

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text(verbatim: summary.project.address.line).font(DSTypography.headline).foregroundStyle(DSColor.textPrimary)
                        Text(verbatim: summary.project.name).font(DSTypography.callout).foregroundStyle(DSColor.textSecondary)
                        Text(verbatim: summary.customerName).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                    }
                    Spacer()
                    StatusBadge(summary.project.status.titleKey, tone: summary.project.status.tone)
                }
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    HStack {
                        Text("home.progress").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                        Spacer()
                        Text(verbatim: "\(progress)%").font(DSTypography.money(.caption)).foregroundStyle(DSColor.textPrimary)
                    }
                    ProgressBar(progress: progress, tone: summary.project.status.tone)
                }
                FormRow("home.contractValue") {
                    MoneyText(amount: summary.project.contractValue.amount, currencyCode: summary.project.contractValue.currency.rawValue, style: .headline)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("project_card_\(summary.project.id.uuidString)")
    }
}
