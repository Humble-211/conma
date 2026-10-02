import SwiftUI

public struct SectionHeader: View {
    private let title: LocalizedStringKey
    private let trailing: AnyView?

    public init(_ title: LocalizedStringKey, trailing: AnyView? = nil) { self.title = title; self.trailing = trailing }

    public var body: some View {
        HStack {
            Text(title).font(DSTypography.title).foregroundStyle(DSColor.textPrimary)
            Spacer()
            if let trailing { trailing }
        }
        .padding(.horizontal, DSSpacing.lg)
    }
}

#Preview {
    VStack(spacing: DSSpacing.md) {
        SectionHeader("gallery.buttons")
        SectionHeader("gallery.badges", trailing: AnyView(StatusBadge("gallery.badge", tone: .info)))
    }
}
