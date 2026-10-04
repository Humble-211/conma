import SwiftUI

public struct ChoiceChips<T: Hashable>: View {
    private let options: [T]
    @Binding private var selection: T?
    private let text: (T) -> Text
    private let identifier: ((T) -> String)?

    public init(options: [T], selection: Binding<T?>, label: @escaping (T) -> LocalizedStringKey) {
        self.init(options: options, selection: selection, text: { Text(label($0)) }, identifier: nil)
    }

    /// `text` lets callers show user data verbatim (custom category names); `identifier` names each chip for UI tests.
    public init(options: [T], selection: Binding<T?>, text: @escaping (T) -> Text, identifier: ((T) -> String)? = nil) {
        self.options = options; _selection = selection; self.text = text; self.identifier = identifier
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.sm) {
                ForEach(options, id: \.self) { option in
                    let selected = option == selection
                    Button { selection = selected ? nil : option } label: {
                        text(option)
                            .font(DSTypography.callout.weight(.medium))
                            .padding(.horizontal, DSSpacing.md).padding(.vertical, DSSpacing.sm)
                            .frame(minHeight: DSSpacing.minTouch)
                            .background(selected ? DSColor.accent : DSColor.surface, in: Capsule())
                            .foregroundStyle(selected ? DSColor.onAccent : DSColor.textPrimary)
                            .overlay(Capsule().strokeBorder(DSColor.border, lineWidth: selected ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .modifier(ChipIdentifier(id: identifier?(option)))
                }
            }
            .padding(.horizontal, DSSpacing.lg)
        }
    }
}

private struct ChipIdentifier: ViewModifier {
    let id: String?
    func body(content: Content) -> some View {
        if let id { content.accessibilityIdentifier(id) } else { content }
    }
}
