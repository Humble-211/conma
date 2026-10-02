import SwiftUI

public struct MoneyText: View {
    private let amount: Decimal
    private let currencyCode: String
    private let style: Font.TextStyle
    @Environment(\.locale) private var locale

    public init(amount: Decimal, currencyCode: String, style: Font.TextStyle = .body) {
        self.amount = amount; self.currencyCode = currencyCode; self.style = style
    }

    public var body: some View {
        Text(amount, format: .currency(code: currencyCode).locale(locale).precision(.fractionLength(2)))
            .font(DSTypography.money(style))
    }
}

#Preview {
    VStack(alignment: .leading, spacing: DSSpacing.md) {
        MoneyText(amount: Decimal(string: "38000.00") ?? 0, currencyCode: "CAD")
        MoneyText(amount: Decimal(550), currencyCode: "CAD", style: .headline)
    }
    .padding()
}
