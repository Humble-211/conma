import SwiftUI

/// Actual progress drawn over the expected (time-based) progress, with a legend.
public struct DualProgressBar: View {
    private let expected: Int?
    private let actual: Int
    private let expectedLabel: LocalizedStringKey
    private let actualLabel: LocalizedStringKey

    public init(expected: Int?, actual: Int, expectedLabel: LocalizedStringKey, actualLabel: LocalizedStringKey) {
        self.expected = expected; self.actual = actual; self.expectedLabel = expectedLabel; self.actualLabel = actualLabel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DSColor.textSecondary.opacity(0.15))
                    if let e = expected {
                        Capsule().fill(DSColor.textSecondary.opacity(0.35))
                            .frame(width: geo.size.width * CGFloat(Self.clamped(e)) / 100)
                    }
                    Capsule().fill(actualTone.foreground)
                        .frame(width: geo.size.width * CGFloat(Self.clamped(actual)) / 100, height: 6)
                }
            }
            .frame(height: 10)
            HStack(spacing: DSSpacing.md) {
                legend(actualLabel, "\(actual)%", actualTone.foreground)
                if let e = expected { legend(expectedLabel, "\(e)%", DSColor.textSecondary) }
            }
            .font(DSTypography.caption)
        }
    }

    private static func clamped(_ value: Int) -> Int { min(100, max(0, value)) }

    private var actualTone: DSTone {
        if let e = expected, actual + 10 < e { return .warning }
        return .accent
    }

    private func legend(_ title: LocalizedStringKey, _ value: String, _ color: Color) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title)
            Text(verbatim: value).font(DSTypography.money(.caption))
        }
        .foregroundStyle(DSColor.textSecondary)
    }
}

#Preview {
    VStack(spacing: DSSpacing.lg) {
        DualProgressBar(expected: 40, actual: 65, expectedLabel: "gallery.expected", actualLabel: "gallery.actual")
        DualProgressBar(expected: 80, actual: 30, expectedLabel: "gallery.expected", actualLabel: "gallery.actual")
    }
    .padding()
}
