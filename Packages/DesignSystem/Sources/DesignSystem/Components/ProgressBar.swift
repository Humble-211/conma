import SwiftUI

public struct ProgressBar: View {
    private let progress: Int
    private let tone: DSTone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(progress: Int, tone: DSTone = .accent) {
        self.progress = min(max(progress, 0), 100); self.tone = tone
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(DSColor.border)
                Capsule().fill(tone.foreground)
                    .frame(width: geometry.size.width * CGFloat(progress) / 100)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: progress)
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityValue(Text(verbatim: "\(progress)%"))
    }
}

#Preview {
    VStack(spacing: DSSpacing.md) {
        ProgressBar(progress: 65)
        ProgressBar(progress: 100, tone: .success)
        ProgressBar(progress: 20, tone: .danger)
    }
    .padding()
}
