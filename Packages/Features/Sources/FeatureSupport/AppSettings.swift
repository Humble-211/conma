import SwiftUI
import Observation
import Domain

@Observable
public final class AppSettings {
    public static let languageKey = "settings.language"
    public static let appearanceKey = "settings.appearance"

    public var language: LanguageChoice { didSet { defaults.set(language.rawValue, forKey: AppSettings.languageKey) } }
    public var appearance: AppearanceChoice { didSet { defaults.set(appearance.rawValue, forKey: AppSettings.appearanceKey) } }

    public static let defaultTaxKey = "settings.defaultTaxPercent" // lint:allow-string

    /// Default tax % for NEW expenses (spec §2 "Thuế"); nil = none. Only values accepted by `Percentage.input` are kept.
    public var defaultTaxPercent: Decimal? {
        didSet {
            if let value = defaultTaxPercent { defaults.set(NSDecimalNumber(decimal: value).stringValue, forKey: AppSettings.defaultTaxKey) }
            else { defaults.removeObject(forKey: AppSettings.defaultTaxKey) }
        }
    }

    static func parseTaxPercent(_ raw: String?) -> Decimal? {
        guard let raw, let value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")), (try? Percentage.input(value)) != nil else { return nil } // lint:allow-string
        return value
    }

    private let defaults: UserDefaults
    private let systemLanguageCode: String?

    public init(defaults: UserDefaults = .standard, systemLanguageCode: String? = Locale.current.language.languageCode?.identifier) {
        self.defaults = defaults
        self.systemLanguageCode = systemLanguageCode
        self.language = defaults.string(forKey: AppSettings.languageKey).flatMap(LanguageChoice.init(rawValue:)) ?? .system
        self.appearance = defaults.string(forKey: AppSettings.appearanceKey).flatMap(AppearanceChoice.init(rawValue:)) ?? .system
        self.defaultTaxPercent = AppSettings.parseTaxPercent(defaults.string(forKey: AppSettings.defaultTaxKey))
    }

    /// Vietnamese when chosen, or when the system is Vietnamese and "system" is selected; English otherwise.
    public var resolvedLocale: Locale {
        let languageCode = language.localeIdentifier ?? (systemLanguageCode == "vi" ? "vi" : "en") // lint:allow-string
        var components = Locale.Components(languageCode: Locale.LanguageCode(languageCode))
        components.region = Locale.current.region
        return Locale(components: components)
    }

    public var colorScheme: ColorScheme? { appearance.colorScheme }
}
