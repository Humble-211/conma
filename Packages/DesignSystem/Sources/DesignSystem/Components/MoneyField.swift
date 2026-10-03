import SwiftUI

/// Parses/prints decimals in the environment locale; stores canonical values.
public enum LocaleNumberParser {
    public static func decimal(from text: String, locale: Locale) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.generatesDecimalNumbers = true
        if let number = formatter.number(from: trimmed) as? NSDecimalNumber { return number.decimalValue }
        // Fallback: canonical dot-decimal text (e.g. values typed before a locale switch).
        return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
    }

    public static func string(_ value: Decimal, locale: Locale, fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = fractionDigits
        formatter.usesGroupingSeparator = false
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}

public struct MoneyField: View {
    private let title: LocalizedStringKey
    @Binding private var amount: Decimal?
    private let currencyCode: String
    @Environment(\.locale) private var locale
    @State private var text = ""
    @FocusState private var focused: Bool

    /// `amount` is the Decimal value; callers wrap it into their money type with the company currency.
    public init(_ title: LocalizedStringKey, amount: Binding<Decimal?>, currencyCode: String) {
        self.title = title; _amount = amount; self.currencyCode = currencyCode
    }

    public var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Text(verbatim: currencySymbol).font(DSTypography.money(.title3)).foregroundStyle(DSColor.textSecondary)
            TextField(title, text: $text)
                .keyboardType(.decimalPad)
                .font(DSTypography.money(.title2))
                .multilineTextAlignment(.trailing)
                .focused($focused)
                .onChange(of: text) { _, newValue in amount = LocaleNumberParser.decimal(from: newValue, locale: locale) }
                .onChange(of: focused) { _, isFocused in if !isFocused, let amount { text = LocaleNumberParser.string(amount, locale: locale, fractionDigits: 2) } }
                .onAppear { if let amount { text = LocaleNumberParser.string(amount, locale: locale, fractionDigits: 2) } }
        }
        .frame(minHeight: DSSpacing.minTouch)
    }

    private var currencySymbol: String {
        locale.localizedCurrencySymbol(forCurrencyCode: currencyCode) ?? currencyCode
    }
}

private extension Locale {
    func localizedCurrencySymbol(forCurrencyCode code: String) -> String? {
        var components = Locale.Components(locale: self)
        components.currency = Locale.Currency(code)
        return Locale(components: components).currencySymbol
    }
}
