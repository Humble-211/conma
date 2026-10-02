import SwiftUI
import UIKit

public enum DSColor {
    public static let background = dynamic(light: 0xF5F5F2, dark: 0x0F0F10)
    public static let surface = dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
    public static let textPrimary = dynamic(light: 0x1A1A1A, dark: 0xF2F2F2)
    public static let textSecondary = dynamic(light: 0x5F5F5F, dark: 0xA1A1A6)
    public static let accent = dynamic(light: 0xC2410C, dark: 0xFF8A3D)
    /// Foreground for text/icons placed on `accent` fills (≥ 4.5:1 in both schemes).
    public static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x1A1A1A)
    public static let success = dynamic(light: 0x2E7D4F, dark: 0x4CC38A)
    public static let warning = dynamic(light: 0xB8860B, dark: 0xF0C419)
    public static let danger = dynamic(light: 0xB71C1C, dark: 0xFF6B6B)
    public static let info = dynamic(light: 0x2A5DB0, dark: 0x6FA0FF)
    public static let border = dynamic(light: 0xE2E2DE, dark: 0x2C2C2E)

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

public enum DSTone: Sendable, Hashable, CaseIterable {
    case neutral, info, success, warning, danger, accent

    public var foreground: Color {
        switch self {
        case .neutral: return DSColor.textSecondary
        case .info: return DSColor.info
        case .success: return DSColor.success
        case .warning: return DSColor.warning
        case .danger: return DSColor.danger
        case .accent: return DSColor.accent
        }
    }

    public var background: Color { foreground.opacity(0.14) }
}
