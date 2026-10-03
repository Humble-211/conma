import SwiftUI

public struct FormRow<Content: View>: View {
    private let label: Text
    private let content: Content

    public init(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.label = Text(label); self.content = content()
    }

    public init(verbatimLabel: String, @ViewBuilder content: () -> Content) {
        self.label = Text(verbatim: verbatimLabel); self.content = content()
    }

    public var body: some View {
        HStack(spacing: DSSpacing.md) {
            label.font(DSTypography.body).foregroundStyle(DSColor.textPrimary)
            Spacer(minLength: DSSpacing.md)
            content.multilineTextAlignment(.trailing)
        }
        .frame(minHeight: DSSpacing.minTouch)
    }
}

#Preview {
    Card {
        FormRow("gallery.contractValue") { MoneyText(amount: Decimal(string: "38000.00") ?? 0, currencyCode: "CAD") }
        FormRow("gallery.cashPosition") { MoneyText(amount: Decimal(550), currencyCode: "CAD", style: .headline) }
    }
    .padding()
}
