import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct SettingsView: View {
    @Bindable private var settings: AppSettings
    private let company: Company
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var taxDraft: Decimal?

    public init(settings: AppSettings, company: Company) {
        self.settings = settings; self.company = company
        _taxDraft = State(initialValue: settings.defaultTaxPercent)
    }

    /// > 100 or more than 2 decimals: shown as an error and not saved (spec §5.5).
    private var taxInvalid: Bool { taxDraft.map { (try? Percentage.input($0)) == nil } ?? false }

    public var body: some View {
        Form {
            Section("settings.language") {
                Picker("settings.language", selection: $settings.language) {
                    ForEach(LanguageChoice.allCases, id: \.self) { Text($0.titleKey).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .accessibilityIdentifier("settings_language_picker")
            }
            Section("settings.appearance") {
                Picker("settings.appearance", selection: $settings.appearance) {
                    ForEach(AppearanceChoice.allCases, id: \.self) { Text($0.titleKey).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("settings_appearance_picker")
            }
            Section("settings.tax") {
                FormRow("settings.defaultTax") {
                    DecimalField("settings.defaultTax", value: $taxDraft).accessibilityIdentifier("settings_default_tax")
                }
                if taxInvalid {
                    Text("expense.error.taxPercentOutOfRange").font(DSTypography.caption).foregroundStyle(DSColor.danger)
                    keptTaxText.font(DSTypography.caption).foregroundStyle(DSColor.danger)
                        .accessibilityIdentifier("settings_default_tax_kept")
                } else {
                    Text("settings.defaultTax.hint").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                }
            }
            Section("settings.company") {
                FormRow("settings.company") { Text(verbatim: company.name).foregroundStyle(DSColor.textSecondary) }
                FormRow("settings.currency") { Text(company.currencyCode.titleKey).foregroundStyle(DSColor.textSecondary) }
            }
        }
        // Resolved to a plain string so the title text itself changes with the language: a key-based title
        // compares equal across locales and the navigation bar could keep showing the previous language.
        .navigationTitle(Text(verbatim: LocalizedBundle.string("settings.title", locale: locale)))
        // Saved when leaving the screen (or the app), never per keystroke: typing "1000" must not store 100 on the way.
        .onDisappear(perform: commitTax)
        .onChange(of: scenePhase) { _, phase in if phase != .active { commitTax() } }
    }

    /// The stored default when the typed value is invalid and therefore not saved.
    private var keptTaxText: Text {
        if let stored = settings.defaultTaxPercent {
            return Text("settings.defaultTax.kept \(LocaleNumberParser.string(stored, locale: locale, fractionDigits: 2))")
        }
        return Text("settings.defaultTax.keptNone")
    }

    /// Stores a valid value (or clears an empty field); an invalid value is left unsaved, as the screen says.
    private func commitTax() {
        guard let value = taxDraft else { settings.defaultTaxPercent = nil; return }
        if (try? Percentage.input(value)) != nil, settings.defaultTaxPercent != value { settings.defaultTaxPercent = value }
    }
}
