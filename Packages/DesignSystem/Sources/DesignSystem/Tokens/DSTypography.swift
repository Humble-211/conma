import SwiftUI

public enum DSTypography {
    public static let largeTitle = Font.largeTitle.weight(.bold)
    public static let title = Font.title2.weight(.semibold)
    public static let headline = Font.headline
    public static let body = Font.body
    public static let callout = Font.callout
    public static let caption = Font.caption

    /// Monospaced digits so amounts line up in lists.
    public static func money(_ style: Font.TextStyle = .body) -> Font {
        Font.system(style, design: .default).weight(.semibold).monospacedDigit()
    }
}
