import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct AttentionRow: View {
    let item: AttentionItem
    let projectName: String
    let currency: String
    @Environment(\.locale) private var locale

    var body: some View {
        ActivityRow(systemImage: item.systemImage, title: Text(verbatim: projectName), subtitle: subtitle, tint: item.tone.foreground)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("attention_\(item.id)")
    }

    private var subtitle: Text {
        if case .health(_, let status, let reason) = item {
            return Text(status.titleKey) + Text(verbatim: " · ") + reason.text(currency: currency, locale: locale)
        }
        return item.text(currency: currency, locale: locale)
    }
}
