import SwiftUI

public struct ActivityRow: View {
    private let systemImage: String
    private let title: Text
    private let subtitle: Text
    private let tint: Color?

    public init(systemImage: String, title: Text, subtitle: Text, tint: Color? = nil) {
        self.systemImage = systemImage; self.title = title; self.subtitle = subtitle; self.tint = tint
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DSSpacing.md) {
            Image(systemName: systemImage).foregroundStyle(tint ?? DSColor.accent).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                title.font(DSTypography.callout).foregroundStyle(DSColor.textPrimary)
                subtitle.font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: DSSpacing.minTouch)
    }
}

#Preview {
    ActivityRow(systemImage: "banknote", title: Text("gallery.activityTitle"), subtitle: Text("gallery.activitySubtitle"))
        .padding()
}
