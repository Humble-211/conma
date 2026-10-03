import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// Health status with its localized reasons; terminal projects are not evaluated.
struct HealthSection: View {
    let insights: ProjectInsights?
    let currency: CurrencyCode
    @Environment(\.locale) private var locale

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text("detail.health.title").font(DSTypography.headline)
                if let insights {
                    if let health = insights.health {
                        if health.status == .onTrack {
                            Label("health.status.onTrack", systemImage: "checkmark.circle").foregroundStyle(DSColor.success)
                        } else {
                            HealthChip(health.status.titleKey, tone: health.status.tone)
                            ForEach(health.reasons, id: \.self) { reason in
                                Label { reason.text(currency: currency.rawValue, locale: locale) } icon: {
                                    Image(systemName: "exclamationmark.circle").foregroundStyle(health.status.tone.foreground)
                                }
                                .font(DSTypography.callout)
                            }
                        }
                    } else {
                        Text("health.notEvaluated").font(DSTypography.callout).foregroundStyle(DSColor.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("detail_health_reasons")
    }
}
