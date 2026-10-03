import SwiftUI

public struct ChoiceChips<T: Hashable>: View {
    private let options: [T]
    @Binding private var selection: T?
    private let label: (T) -> LocalizedStringKey

    public init(options: [T], selection: Binding<T?>, label: @escaping (T) -> LocalizedStringKey) {
        self.options = options; _selection = selection; self.label = label
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.sm) {
                ForEach(options, id: \.self) { option in
                    let selected = option == selection
                    Button { selection = selected ? nil : option } label: {
                        Text(label(option))
                            .font(DSTypography.callout.weight(.medium))
                            .padding(.horizontal, DSSpacing.md).padding(.vertical, DSSpacing.sm)
                            .frame(minHeight: DSSpacing.minTouch)
                            .background(selected ? DSColor.accent : DSColor.surface, in: Capsule())
                            .foregroundStyle(selected ? DSColor.onAccent : DSColor.textPrimary)
                            .overlay(Capsule().strokeBorder(DSColor.border, lineWidth: selected ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DSSpacing.lg)
        }
    }
}
