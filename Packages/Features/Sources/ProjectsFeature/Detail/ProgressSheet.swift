import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// Manual progress editor: slider and stepper in steps of 5; "clear" only when a manual value exists.
struct ProgressSheet: View {
    let initial: Int?
    let onSave: (Int?) -> Void
    let onCancel: () -> Void
    @State private var value: Int

    init(initial: Int?, onSave: @escaping (Int?) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial; self.onSave = onSave; self.onCancel = onCancel
        _value = State(initialValue: initial ?? 0)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                Text(verbatim: "\(value)%")
                    .font(DSTypography.money(.largeTitle))
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("progress_value")
                Slider(value: Binding(get: { Double(value) }, set: { value = Int(($0 / 5).rounded()) * 5 }), in: 0...100, step: 5)
                    .accessibilityIdentifier("progress_slider")
                Stepper("progress.manual", value: $value, in: 0...100, step: 5)
                    .accessibilityIdentifier("progress_stepper")
                if initial != nil {
                    Button("progress.clear", role: .destructive) { onSave(nil) }
                        .accessibilityIdentifier("progress_clear")
                }
                Spacer()
            }
            .padding(DSSpacing.lg)
            .background(DSColor.background)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("progress_sheet")
            .navigationTitle("progress.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("sheet.cancel", action: onCancel).accessibilityIdentifier("sheet_cancel") }
                ToolbarItem(placement: .confirmationAction) { Button("progress.save") { onSave(value) }.accessibilityIdentifier("progress_save") }
            }
        }
        .presentationDetents([.medium])
    }
}
