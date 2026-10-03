import SwiftUI

public struct FormRow<Content: View>: View {
    private let label: LocalizedStringKey?
    private let verbatimLabel: String?
    private let content: Content

    public init(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.label = label; self.verbatimLabel = nil; self.content = content()
    }

    public init(verbatimLabel: String, @ViewBuilder content: () -> Content) {
        self.label = nil; self.verbatimLabel = verbatimLabel; self.content = content()
    }

    private var labelText: Text {
        if let verbatimLabel { return Text(verbatim: verbatimLabel) }
        return Text(label ?? "")
    }

    public var body: some View {
        HStack(spacing: DSSpacing.md) {
            labelText.font(DSTypography.body).foregroundStyle(DSColor.textPrimary)
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
