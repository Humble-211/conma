import SwiftUI
import DesignSystem

struct StepFooter: View {
    let canContinue: Bool
    let canSkip: Bool
    let isLast: Bool
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            PrimaryButton(isLast ? "wizard.create" : "wizard.continue", systemImage: isLast ? "checkmark" : "arrow.right", action: onContinue)
                .disabled(!canContinue).opacity(canContinue ? 1 : 0.5)
                .accessibilityIdentifier("wizard_continue")
            if canSkip {
                SecondaryButton("wizard.skip", action: onSkip).accessibilityIdentifier("wizard_skip")
            }
        }
        .padding(.horizontal, DSSpacing.lg).padding(.bottom, DSSpacing.md)
        .background(DSColor.background)
    }
}
