import SwiftUI
import Domain
import DesignSystem

struct AttentionListSheet: View {
    let items: [AttentionItem]
    let names: [UUID: String]
    let currency: String
    let onSelect: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(items) { item in
                Button { onSelect(item.projectId) } label: {
                    AttentionRow(item: item, projectName: names[item.projectId] ?? "", currency: currency)
                }
                .buttonStyle(.plain)
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
