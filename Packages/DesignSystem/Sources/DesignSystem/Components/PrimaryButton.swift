import SwiftUI

public struct PrimaryButton: View {
    private let title: LocalizedStringKey
    private let systemImage: String?
    private let isLoading: Bool
    private let action: () -> Void

    public init(_ title: LocalizedStringKey, systemImage: String? = nil, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.isLoading = isLoading; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.sm) {
                if isLoading {
                    ProgressView().tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title).font(DSTypography.headline)
            }
            .frame(maxWidth: .infinity, minHeight: DSSpacing.primaryButtonHeight)
            .foregroundStyle(.white)
            .background(DSColor.accent, in: RoundedRectangle(cornerRadius: DSSpacing.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

#Preview {
    VStack(spacing: DSSpacing.md) {
        PrimaryButton("gallery.primaryButton", systemImage: "plus") {}
        PrimaryButton("gallery.loadingButton", isLoading: true) {}
    }
    .padding()
}
