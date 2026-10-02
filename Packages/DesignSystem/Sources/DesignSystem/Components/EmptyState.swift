import SwiftUI

public struct EmptyState: View {
    private let systemImage: String
    private let title: LocalizedStringKey
    private let message: LocalizedStringKey

    public init(systemImage: String, title: LocalizedStringKey, message: LocalizedStringKey) {
        self.systemImage = systemImage; self.title = title; self.message = message
    }

    public var body: some View {
        VStack(spacing: DSSpacing.md) {
            Image(systemName: systemImage).font(.system(size: 44)).foregroundStyle(DSColor.textSecondary)
            Text(title).font(DSTypography.title).foregroundStyle(DSColor.textPrimary)
            Text(message).font(DSTypography.body).foregroundStyle(DSColor.textSecondary).multilineTextAlignment(.center)
        }
        .padding(DSSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EmptyState(systemImage: "tray", title: "gallery.emptyTitle", message: "gallery.emptyMessage")
}
