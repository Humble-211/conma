import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct AttentionListSheet: View {
    let items: [AttentionItem]
    let names: [UUID: String]
    let onSelect: (UUID) -> Void
    let onRecord: ((AttentionItem) -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(items) { item in
                HStack(spacing: DSSpacing.sm) {
                    Button { onSelect(item.projectId) } label: { AttentionRow(item: item, projectName: names[item.projectId] ?? "") }
                        .buttonStyle(.plain)
                    if let onRecord, let itemId = item.scheduleItemId {
                        Button("attention.record") { onRecord(item) }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(item.recordAccessibilityLabel(projectName: names[item.projectId] ?? ""))
                            .accessibilityIdentifier("attention_record_\(itemId.uuidString)")
                    }
                }
            }
            .navigationTitle("home.attention.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("home.attention.done") { dismiss() } }
            }
        }
        .accessibilityIdentifier("home_attention_sheet")
    }
}
