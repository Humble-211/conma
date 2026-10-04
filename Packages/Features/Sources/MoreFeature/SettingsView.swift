import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct SettingsView: View {
    @Bindable private var settings: AppSettings
    private let company: Company
    @Environment(\.locale) private var locale
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
                } else {
                    Text("settings.defaultTax.hint").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                }
            }
            .onChange(of: taxDraft) { _, value in
                if let value {
                    if (try? Percentage.input(value)) != nil { settings.defaultTaxPercent = value }
                } else {
                    settings.defaultTaxPercent = nil
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
    }
}
