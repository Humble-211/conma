import SwiftUI

/// Redacted placeholder card shown until the first data emission.
public struct SkeletonCard: View {
    private let lines: Int

    public init(lines: Int = 3) { self.lines = lines }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                ForEach(0..<max(1, lines), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DSColor.textSecondary.opacity(0.15))
                        .frame(width: i == 0 ? 160 : 240, height: 14)
                }
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

#Preview {
    SkeletonCard().padding()
}
