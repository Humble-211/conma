import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// All 13 statuses grouped by phase; each row shows the title and a one-line hint.
struct StatusPickerSheet: View {
    let current: ProjectStatus
    let onPick: (ProjectStatus) -> Void
    @Environment(\.dismiss) private var dismiss

    private static let phases: [ProjectPhase] = [.preStart, .inWork, .workDone, .terminal]

    var body: some View {
        NavigationStack {
            List {
                ForEach(Self.phases, id: \.self) { phase in
                    Section(Self.phaseKey(phase)) {
                        ForEach(ProjectStatus.allCases.filter { $0.phase == phase }, id: \.self) { status in
                            Button { onPick(status) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                                        Text(status.titleKey).foregroundStyle(DSColor.textPrimary)
                                        Text(status.hintKey).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                                    }
                                    Spacer()
                                    if status == current { Image(systemName: "checkmark").foregroundStyle(DSColor.accent) }
                                }
                                .contentShape(Rectangle())
                            }
                            .accessibilityIdentifier("status_" + status.rawValue)
                        }
                    }
                }
            }
            .accessibilityIdentifier("status_picker")
            .navigationTitle("detail.status.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("sheet.cancel") { dismiss() }.accessibilityIdentifier("sheet_cancel") }
            }
        }
    }

    private static func phaseKey(_ phase: ProjectPhase) -> LocalizedStringKey {
        switch phase {
        case .preStart: return "status.phase.preStart"
        case .inWork: return "status.phase.inWork"
        case .workDone: return "status.phase.workDone"
        case .terminal: return "status.phase.terminal"
        }
    }
}
