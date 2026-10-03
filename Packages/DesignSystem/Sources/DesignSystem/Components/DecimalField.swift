import SwiftUI

public struct DecimalField: View {
    private let title: LocalizedStringKey
    @Binding private var value: Decimal?
    private let fractionDigits: Int
    @Environment(\.locale) private var locale
    @State private var text = ""
    @FocusState private var focused: Bool

    public init(_ title: LocalizedStringKey, value: Binding<Decimal?>, fractionDigits: Int = 2) {
        self.title = title; _value = value; self.fractionDigits = fractionDigits
    }

    public var body: some View {
        TextField(title, text: $text)
            .keyboardType(.decimalPad)
            .font(DSTypography.money(.body))
            .multilineTextAlignment(.trailing)
            .focused($focused)
            .onChange(of: text) { _, newValue in value = LocaleNumberParser.decimal(from: newValue, locale: locale) }
            .onChange(of: focused) { _, isFocused in if !isFocused, let value { text = LocaleNumberParser.string(value, locale: locale, fractionDigits: fractionDigits) } }
            .onAppear { if let value { text = LocaleNumberParser.string(value, locale: locale, fractionDigits: fractionDigits) } }
            .frame(minHeight: DSSpacing.minTouch)
    }
}

public struct IntegerField: View {
    private let title: LocalizedStringKey
    @Binding private var value: Int?
    @State private var text = ""

    public init(_ title: LocalizedStringKey, value: Binding<Int?>) { self.title = title; _value = value }

    public var body: some View {
        TextField(title, text: $text)
            .keyboardType(.numberPad)
            .font(DSTypography.money(.body))
            .multilineTextAlignment(.trailing)
            .onChange(of: text) { _, newValue in value = Int(newValue.filter(\.isNumber)) }
            .onAppear { if let value { text = String(value) } }
            .frame(minHeight: DSSpacing.minTouch)
    }
}
