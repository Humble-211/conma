import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct DraftBanner: View {
    private let draft: ProjectDraft
    private let onContinue: () -> Void
    private let onDiscard: () -> Void

    public init(draft: ProjectDraft, onContinue: @escaping () -> Void, onDiscard: @escaping () -> Void) {
        self.draft = draft; self.onContinue = onContinue; self.onDiscard = onDiscard
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text("draft.title").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                HStack {
                    VStack(alignment: .leading) {
                        if let line = draft.address?.line, !line.isEmpty { Text(verbatim: line).font(DSTypography.headline) }
                        else if let type = draft.jobType { Text(type.titleKey).font(DSTypography.headline) }
                        else { Text("draft.untitled").font(DSTypography.headline) }
                        Text(verbatim: "\(draft.step)/\(WizardStep.total)").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                    }
                    Spacer()
                    Button("draft.discard", role: .destructive, action: onDiscard).accessibilityIdentifier("draft_discard")
                    Button("draft.continue", action: onContinue).buttonStyle(.borderedProminent).tint(DSColor.accent).accessibilityIdentifier("draft_continue")
                }
            }
        }
        .accessibilityIdentifier("draft_banner")
    }
}
