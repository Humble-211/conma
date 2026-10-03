import SwiftUI
import Domain
import DesignSystem

public struct ProjectCardView: View {
    let project: Project
    let customerName: String
    let insights: ProjectInsights?
    let progress: Int
    @Environment(\.timeZone) private var timeZone

    /// `insights == nil` (e.g. the Projects list) hides the money row and the health chip.
    public init(project: Project, customerName: String, insights: ProjectInsights?, progress: Int) {
        self.project = project; self.customerName = customerName; self.insights = insights; self.progress = progress
    }

    /// 2a call sites.
    public init(summary: ProjectSummary, progress: Int) {
        self.init(project: summary.project, customerName: summary.customerName, insights: nil, progress: progress)
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text(verbatim: project.address.line).font(DSTypography.headline).foregroundStyle(DSColor.textPrimary)
                        Text(verbatim: project.name).font(DSTypography.callout).foregroundStyle(DSColor.textSecondary)
                        Text(verbatim: customerName).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: DSSpacing.xs) {
                        StatusBadge(project.status.titleKey, tone: project.status.tone)
                        if let health = insights?.health {
                            HealthChip(health.status.titleKey, tone: health.status.tone)
                                .accessibilityIdentifier("card_health")
                        }
                    }
                }
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    HStack {
                        Text("home.progress").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                        Spacer()
                        Text(verbatim: "\(progress)%").font(DSTypography.money(.caption)).foregroundStyle(DSColor.textPrimary)
                    }
                    ProgressBar(progress: progress, tone: project.status.tone)
                }
                if let f = insights?.financials {
                    HStack(spacing: DSSpacing.sm) {
                        stat("home.card.spent", f.spentSoFar)
                        Divider()
                        stat("home.card.collected", f.collected)
                        Divider()
                        stat("home.card.cash", f.cashPosition, tone: f.cashPosition.isNegative ? .danger : .neutral)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                } else {
                    FormRow("home.contractValue") {
                        MoneyText(amount: project.contractValue.amount, currencyCode: project.contractValue.currency.rawValue, style: .headline)
                    }
                }
                if let start = project.startDate, let end = project.estimatedCompletionDate {
                    HStack(spacing: DSSpacing.xs) {
                        DateLabel(start.noonDate(in: timeZone))
                        Text(verbatim: "→")
                        DateLabel(end.noonDate(in: timeZone))
                    }
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColor.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("project_card_\(project.id.uuidString)")
    }

    private func stat(_ title: LocalizedStringKey, _ money: Money, tone: DSTone = .neutral) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
            MoneyText(amount: money.amount, currencyCode: money.currency.rawValue, style: .callout)
                .foregroundStyle(tone == .danger ? DSColor.danger : DSColor.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
