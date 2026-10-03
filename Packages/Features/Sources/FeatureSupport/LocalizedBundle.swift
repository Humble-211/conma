import Foundation

public enum LocalizedBundle {
    /// Resolves a catalog key in the app's chosen language (not the device language).
    public static func string(_ key: String, locale: Locale) -> String {
        let code = locale.language.languageCode?.identifier ?? "en" // lint:allow-string
        let bundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? Bundle.main // lint:allow-string
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
