import SwiftUI

public struct FloatingActionButton: View {
    private let systemImage: String
    private let accessibilityLabel: LocalizedStringKey
    private let action: () -> Void

    public init(systemImage: String = "plus", accessibilityLabel: LocalizedStringKey, action: @escaping () -> Void) {
        self.systemImage = systemImage; self.accessibilityLabel = accessibilityLabel; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(DSColor.accent, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

#Preview {
    FloatingActionButton(accessibilityLabel: "gallery.add") {}
        .padding()
}
