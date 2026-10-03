import SwiftUI

public struct StepHeader: View {
    private let title: LocalizedStringKey
    private let step: Int
    private let total: Int

    public init(title: LocalizedStringKey, step: Int, total: Int) { self.title = title; self.step = step; self.total = total }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Text(title).font(DSTypography.title).foregroundStyle(DSColor.textPrimary)
                Spacer()
                Text(verbatim: "\(step)/\(total)").font(DSTypography.money(.callout)).foregroundStyle(DSColor.textSecondary)
            }
            ProgressBar(progress: Int((Double(step) / Double(max(total, 1)) * 100).rounded()))
        }
        .padding(.horizontal, DSSpacing.lg)
    }
}
