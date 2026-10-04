import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// "More" from the form: all 13 built-ins, the live custom categories and quick "New category".
struct CategoryPickerSheet: View {
    let viewModel: ExpenseFormViewModel
    let onDone: () -> Void
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                Section("categories.builtIn") {
                    ForEach(ExpenseCategoryChoice.defaultOrder, id: \.self) { category in
                        row(.standard(category), title: Text(category.titleKey), icon: category.systemImage, group: category.defaultCostGroup)
                            .accessibilityIdentifier("category_pick_" + category.rawValue)
                    }
                }
                Section("category.picker.custom") {
                    ForEach(Array(viewModel.liveCustomCategories.enumerated()), id: \.element.id) { index, category in
                        row(.custom(category.id), title: Text(verbatim: category.name), icon: "tag", group: category.costGroup)
                            .accessibilityIdentifier("category_pick_custom_\(index)")
                    }
                    Button { creating = true } label: { Label("category.picker.new", systemImage: "plus") }
                        .accessibilityIdentifier("category_picker_new")
                }
            }
            .accessibilityIdentifier("category_picker")
            .navigationTitle("category.picker.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("sheet.cancel", action: onDone).accessibilityIdentifier("sheet_cancel") }
            }
            .sheet(isPresented: $creating) {
                CategoryEditSheet(usage: nil, onSave: { name, group in
                    let key = await viewModel.createCategory(name: name, group: group)
                    if key == nil { creating = false; onDone() }
                    return key
                }, onDelete: nil, onCancel: { creating = false })
            }
        }
    }

    private func row(_ choice: ExpenseCategoryChoice, title: Text, icon: String, group: CostGroup?) -> some View {
        Button {
            viewModel.draft.category = choice
            onDone()
        } label: {
            HStack {
                Label { title } icon: { Image(systemName: icon) }
                    .foregroundStyle(DSColor.textPrimary)
                Spacer()
                if let group { Text(group.titleKey).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
                if viewModel.draft.category == choice { Image(systemName: "checkmark").foregroundStyle(DSColor.accent) }
            }
            .frame(minHeight: DSSpacing.minTouch)
        }
        .accessibilityElement(children: .combine)
    }
}
