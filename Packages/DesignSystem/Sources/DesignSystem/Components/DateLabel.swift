import SwiftUI

public struct DateLabel: View {
    public enum Style: Sendable, Hashable { case short, full }
    private let date: Date
    private let style: Style
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    public init(_ date: Date, style: Style = .short) { self.date = date; self.style = style }

    public var body: some View {
        Text(verbatim: Self.string(date, style: style, locale: locale, timeZone: timeZone))
    }

    /// DateFormatter honours the in-app locale override; `Text(date, format:)` does not.
    public static func string(_ date: Date, style: Style, locale: Locale, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = locale; f.timeZone = timeZone
        f.dateStyle = style == .short ? .medium : .full
        f.timeStyle = .none
        return f.string(from: date)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: DSSpacing.sm) {
        DateLabel(Date())
        DateLabel(Date(), style: .full)
    }
    .padding()
}
