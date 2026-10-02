import SwiftUI

public struct SecondaryButton: View {
    private let title: LocalizedStringKey
    private let systemImage: String?
    private let action: () -> Void

    public init(_ title: LocalizedStringKey, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.sm) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title).font(DSTypography.headline)
            }
            .frame(maxWidth: .infinity, minHeight: DSSpacing.primaryButtonHeight)
            .foregroundStyle(DSColor.accent)
            .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DSSpacing.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DSSpacing.cardRadius, style: .continuous).strokeBorder(DSColor.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: DSSpacing.md) {
        SecondaryButton("gallery.secondaryButton", systemImage: "camera") {}
        SecondaryButton("gallery.secondaryButton") {}
    }
    .padding()
}
