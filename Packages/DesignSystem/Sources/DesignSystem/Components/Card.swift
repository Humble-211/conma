import SwiftUI

public struct Card<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        content
            .padding(DSSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DSSpacing.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DSSpacing.cardRadius, style: .continuous).strokeBorder(DSColor.border, lineWidth: 1))
    }
}

#Preview {
    Card {
        Text("gallery.title")
    }
    .padding()
}
