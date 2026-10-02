import SwiftUI

public struct SummaryTile: View {
    private let title: LocalizedStringKey
    private let value: Text
    private let tone: DSTone

    public init(_ title: LocalizedStringKey, value: Text, tone: DSTone = .neutral) {
        self.title = title; self.value = value; self.tone = tone
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(title).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                value.font(DSTypography.money(.title3)).foregroundStyle(tone == .neutral ? DSColor.textPrimary : tone.foreground)
            }
        }
    }
}

#Preview {
    HStack(spacing: DSSpacing.md) {
        SummaryTile("gallery.collected", value: Text(Decimal(20_000), format: .currency(code: "CAD")), tone: .success)
        SummaryTile("gallery.spent", value: Text(Decimal(19_450), format: .currency(code: "CAD")), tone: .danger)
    }
    .padding()
}
