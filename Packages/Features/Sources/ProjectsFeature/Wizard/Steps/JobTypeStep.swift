import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct JobTypeStep: View {
    @Bindable var viewModel: ProjectWizardViewModel
    private let columns = [GridItem(.flexible(), spacing: DSSpacing.md), GridItem(.flexible(), spacing: DSSpacing.md)]

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            LazyVGrid(columns: columns, spacing: DSSpacing.md) {
                ForEach(JobType.allCases, id: \.self) { type in
                    let selected = viewModel.draft.jobType == type
                    Button { select(type) } label: {
                        VStack(spacing: DSSpacing.sm) {
                            Image(systemName: Self.symbol(for: type)).font(.title2)
                            Text(type.titleKey).font(DSTypography.callout.weight(.medium)).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 88)
                        .padding(DSSpacing.sm)
                        .background(selected ? DSColor.accent : DSColor.surface, in: RoundedRectangle(cornerRadius: DSSpacing.cardRadius, style: .continuous))
                        .foregroundStyle(selected ? DSColor.onAccent : DSColor.textPrimary)
                        .overlay(RoundedRectangle(cornerRadius: DSSpacing.cardRadius, style: .continuous).strokeBorder(DSColor.border, lineWidth: selected ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("wizard_jobtype_" + type.rawValue)
                }
            }
            .padding(.horizontal, DSSpacing.lg)
            if viewModel.draft.jobType == .other {
                Card {
                    TextField("wizard.jobType.customPlaceholder", text: Binding(get: { viewModel.draft.customJobType ?? "" }, set: { viewModel.draft.customJobType = $0 }))
                        .frame(minHeight: DSSpacing.minTouch)
                        .accessibilityIdentifier("wizard_custom_jobtype")
                }
                .padding(.horizontal, DSSpacing.lg)
            }
        }
    }

    private func select(_ type: JobType) {
        if viewModel.draft.jobType != type && !viewModel.draft.scopeFields.isEmpty {
            viewModel.pendingJobTypeChange = type   // Task 14 adds the keep/clear dialog
        } else {
            viewModel.draft.jobType = type
        }
        if type != .other { viewModel.draft.customJobType = nil }
    }

    static func symbol(for type: JobType) -> String {
        let systemName: String
        switch type {
        case .generalRenovation: systemName = "hammer"
        case .basementRenovation: systemName = "stairs"
        case .kitchen: systemName = "fork.knife"
        case .bathroom: systemName = "shower"
        case .landscaping: systemName = "leaf"
        case .roofing: systemName = "house"
        case .plumbing: systemName = "drop"
        case .electrical: systemName = "bolt"
        case .hvac: systemName = "wind"
        case .flooring: systemName = "square.grid.3x3"
        case .painting: systemName = "paintbrush"
        case .drywall: systemName = "rectangle.split.2x1"
        case .concrete: systemName = "cube"
        case .deckFence: systemName = "fence"
        case .framing: systemName = "ruler"
        case .windowsDoors: systemName = "door.left.hand.open"
        case .exterior: systemName = "building.2"
        case .demolition: systemName = "trash"
        case .commercial: systemName = "building"
        case .other: systemName = "ellipsis.circle"
        }
        return systemName
    }
}
