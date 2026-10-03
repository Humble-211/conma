import SwiftUI

/// Compact semantic status chip (project health): coloured dot + title.
public struct HealthChip: View {
    private let title: LocalizedStringKey
    private let tone: DSTone

    public init(_ title: LocalizedStringKey, tone: DSTone) { self.title = title; self.tone = tone }

    public var body: some View {
        Label { Text(title) } icon: { Circle().fill(tone.foreground).frame(width: 8, height: 8) }
            .font(DSTypography.caption)
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .background(tone.foreground.opacity(0.12), in: Capsule())
    }
}

#Preview {
    HStack(spacing: DSSpacing.sm) {
        HealthChip("gallery.badge", tone: .success)
        HealthChip("gallery.badge", tone: .danger)
    }
    .padding()
}
