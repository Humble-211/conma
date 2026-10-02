import SwiftUI

public enum AppearanceChoice: String, CaseIterable, Sendable {
    case system, light, dark

    public var titleKey: LocalizedStringKey {
        switch self {
        case .system: return "appearance.system"
        case .light: return "appearance.light"
        case .dark: return "appearance.dark"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
