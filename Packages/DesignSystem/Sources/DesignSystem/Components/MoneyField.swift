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

    /// Whether a field showing `text` must be rewritten after its bound value changed to `newValue`.
    /// Unfocused: always (canonical display). Focused: only when the text means a different value,
    /// treating empty and zero as the same value both ways: clearing a field whose binding stores 0 is not
    /// refilled with "0", and zero-valued text ("0.", "0.0") is not wiped by a binding that maps 0 to nil.
    public static func shouldReplace(_ text: String, with newValue: Decimal?, focused: Bool, locale: Locale) -> Bool {
        guard focused else { return true }
        return !sameWhileTyping(decimal(from: text, locale: locale), newValue)
    }

    /// Equal, or one is nil and the other is zero (shared with `IntegerField`).
    public static func sameWhileTyping<T: Equatable & ExpressibleByIntegerLiteral>(_ shown: T?, _ value: T?) -> Bool {
        if shown == value { return true }
        if shown == nil, value == 0 { return true }
        if shown == 0, value == nil { return true }
        return false
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
    private let autoFocus: Bool
    @Environment(\.locale) private var locale
    @State private var text = ""
    @FocusState private var focused: Bool

    /// `amount` is the Decimal value; callers wrap it into their money type with the company currency.
    public init(_ title: LocalizedStringKey, amount: Binding<Decimal?>, currencyCode: String, autoFocus: Bool = false) {
        self.title = title; _amount = amount; self.currencyCode = currencyCode; self.autoFocus = autoFocus
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
                .onChange(of: amount) { _, newValue in
                    // Outside changes (a chip, a recompute) must show even while the keyboard is up;
                    // the user's own in-progress text stays when it already means the same value.
                    if LocaleNumberParser.shouldReplace(text, with: newValue, focused: focused, locale: locale) {
                        text = newValue.map { LocaleNumberParser.string($0, locale: locale, fractionDigits: 2) } ?? ""
                    }
                }
                .task { if autoFocus { try? await Task.sleep(for: .milliseconds(350)); focused = true } }
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
