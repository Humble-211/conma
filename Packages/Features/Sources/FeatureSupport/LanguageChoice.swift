import SwiftUI

public enum LanguageChoice: String, CaseIterable, Sendable {
    case system, english, vietnamese

    public var titleKey: LocalizedStringKey {
        switch self {
        case .system: return "language.system"
        case .english: return "language.english"
        case .vietnamese: return "language.vietnamese"
        }
    }

    /// nil = follow the system.
    var localeIdentifier: String? {
        switch self {
        case .system: return nil
        case .english: return "en" // lint:allow-string
        case .vietnamese: return "vi" // lint:allow-string
        }
    }
}
