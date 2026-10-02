import SwiftUI

public struct StatusBadge: View {
    private let title: LocalizedStringKey
    private let tone: DSTone

    public init(_ title: LocalizedStringKey, tone: DSTone) { self.title = title; self.tone = tone }

    public var body: some View {
        Text(title)
            .font(DSTypography.caption.weight(.semibold))
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .foregroundStyle(tone.foreground)
            .background(tone.background, in: Capsule())
    }
}

#Preview {
    HStack(spacing: DSSpacing.sm) {
        ForEach(DSTone.allCases, id: \.self) { tone in
            StatusBadge("gallery.badge", tone: tone)
        }
    }
    .padding()
}
