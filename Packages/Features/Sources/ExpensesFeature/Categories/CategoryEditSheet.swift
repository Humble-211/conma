import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// New (usage == nil) or existing category. The group chips are disabled once any expense used the category.
public struct CategoryEditSheet: View {
    private let usage: CustomCategoryUsage?
    private let onSave: (String, CostGroup) async -> LocalizedStringKey?
    private let onDelete: (() async -> LocalizedStringKey?)?
    private let onCancel: () -> Void
    @State private var name: String
    @State private var group: CostGroup
    @State private var errorKey: LocalizedStringKey?
    @State private var saving = false

    public init(usage: CustomCategoryUsage?, onSave: @escaping (String, CostGroup) async -> LocalizedStringKey?,
                onDelete: (() async -> LocalizedStringKey?)?, onCancel: @escaping () -> Void) {
        self.usage = usage; self.onSave = onSave; self.onDelete = onDelete; self.onCancel = onCancel
        _name = State(initialValue: usage?.category.name ?? "")
        _group = State(initialValue: usage?.category.costGroup ?? .other)
    }

    private var locked: Bool { usage?.everUsed ?? false }
    private var titleKey: LocalizedStringKey { usage == nil ? "categories.new.title" : "categories.edit.title" }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("categories.name", text: $name).accessibilityIdentifier("category_name")
                }
                Section("categories.group") {
                    ChoiceChips(options: CostGroup.allCases, selection: Binding(get: { group }, set: { if let g = $0 { group = g } }),
                                text: { Text($0.titleKey) }, identifier: { "category_group_" + $0.rawValue })
                        .disabled(locked)
                        .listRowInsets(EdgeInsets(top: DSSpacing.sm, leading: 0, bottom: DSSpacing.sm, trailing: 0))
                    if locked {
                        Text("categories.groupLocked")
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColor.textSecondary)
                            .accessibilityIdentifier("category_group_locked")
                    }
                }
                if let errorKey {
                    Text(errorKey).foregroundStyle(DSColor.danger).accessibilityIdentifier("category_error")
                }
                if let usage, let onDelete {
                    if usage.liveExpenseCount == 0 {
                        Button("categories.delete", role: .destructive) { Task { errorKey = await onDelete() } }
                            .accessibilityIdentifier("category_delete")
                    } else {
                        Text("categories.deleteBlocked")
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColor.textSecondary)
                            .accessibilityIdentifier("category_delete_blocked")
                    }
                }
            }
            .navigationTitle(titleKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("sheet.cancel", action: onCancel).accessibilityIdentifier("sheet_cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("sheet.save") { Task { saving = true; errorKey = await onSave(name, group); saving = false } }
                        .disabled(saving)
                        .accessibilityIdentifier("category_save")
                }
            }
        }
    }
}
