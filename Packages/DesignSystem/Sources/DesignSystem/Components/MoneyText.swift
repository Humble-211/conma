import SwiftUI

/// The single money formatting rule (currency, explicit locale, two fraction digits),
/// shared by `MoneyText` and by localized sentences that embed an amount.
public enum MoneyFormat {
    public static func string(_ amount: Decimal, currencyCode: String, locale: Locale) -> String {
        amount.formatted(.currency(code: currencyCode).locale(locale).precision(.fractionLength(2)))
    }
}

public struct MoneyText: View {
    private let amount: Decimal
    private let currencyCode: String
    private let style: Font.TextStyle
    @Environment(\.locale) private var locale

    public init(amount: Decimal, currencyCode: String, style: Font.TextStyle = .body) {
        self.amount = amount; self.currencyCode = currencyCode; self.style = style
    }

    public var body: some View {
        Text(verbatim: MoneyFormat.string(amount, currencyCode: currencyCode, locale: locale))
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
