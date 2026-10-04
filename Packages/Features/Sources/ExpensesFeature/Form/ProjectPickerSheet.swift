import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// Every live project, grouped by phase (late receipts for closed jobs can still be logged).
struct ProjectPickerSheet: View {
    let projects: [Project]
    let selected: UUID?
    let onPick: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    private static let phases: [ProjectPhase] = [.inWork, .preStart, .workDone, .terminal]

    var body: some View {
        NavigationStack {
            List {
                ForEach(Self.phases, id: \.self) { phase in
                    let items = Array(projects.enumerated()).filter { $0.element.status.phase == phase }
                    if !items.isEmpty {
                        Section {
                            ForEach(items, id: \.element.id) { index, project in
                                Button { onPick(project.id) } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(verbatim: project.name).foregroundStyle(DSColor.textPrimary)
                                            Text(verbatim: project.address.line).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                                        }
                                        Spacer()
                                        if project.id == selected { Image(systemName: "checkmark").foregroundStyle(DSColor.accent) }
                                    }
                                    .frame(minHeight: DSSpacing.minTouch)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("project_pick_\(index)")
                            }
                        } header: {
                            Text(Self.phaseKey(phase))
                        }
                    }
                }
            }
            .accessibilityIdentifier("project_picker")
            .navigationTitle("project.picker.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("sheet.cancel") { dismiss() }.accessibilityIdentifier("sheet_cancel") }
            }
        }
    }

    private static func phaseKey(_ phase: ProjectPhase) -> LocalizedStringKey {
        switch phase {
        case .inWork: return "status.phase.inWork"
        case .preStart: return "status.phase.preStart"
        case .workDone: return "status.phase.workDone"
        case .terminal: return "status.phase.terminal"
        }
    }
}
