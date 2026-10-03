import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct SettingsView: View {
    @Bindable private var settings: AppSettings
    private let company: Company
    @Environment(\.locale) private var locale

    public init(settings: AppSettings, company: Company) { self.settings = settings; self.company = company }

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
