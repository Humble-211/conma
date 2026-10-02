import SwiftUI
import Observation

@Observable
public final class AppSettings {
    public static let languageKey = "settings.language"
    public static let appearanceKey = "settings.appearance"

    public var language: LanguageChoice { didSet { defaults.set(language.rawValue, forKey: AppSettings.languageKey) } }
    public var appearance: AppearanceChoice { didSet { defaults.set(appearance.rawValue, forKey: AppSettings.appearanceKey) } }

    private let defaults: UserDefaults
    private let systemLanguageCode: String?

    public init(defaults: UserDefaults = .standard, systemLanguageCode: String? = Locale.current.language.languageCode?.identifier) {
        self.defaults = defaults
        self.systemLanguageCode = systemLanguageCode
        self.language = defaults.string(forKey: AppSettings.languageKey).flatMap(LanguageChoice.init(rawValue:)) ?? .system
        self.appearance = defaults.string(forKey: AppSettings.appearanceKey).flatMap(AppearanceChoice.init(rawValue:)) ?? .system
    }

    /// Vietnamese when chosen, or when the system is Vietnamese and "system" is selected; English otherwise.
    public var resolvedLocale: Locale {
        let code = language.localeIdentifier ?? (systemLanguageCode == "vi" ? "vi" : "en") // lint:allow-string
        return Locale(identifier: code)
    }

    public var colorScheme: ColorScheme? { appearance.colorScheme }
}
