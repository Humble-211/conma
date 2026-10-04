import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// More → Expense categories: the company's custom categories (editable) above the 13 read-only built-ins.
public struct CategoriesView: View {
    @Bindable var viewModel: CategoriesViewModel
    @State private var editing: EditTarget?

    enum EditTarget: Identifiable {
        case new
        case existing(CustomCategoryUsage)
        var id: String {
            switch self {
            case .new: return "new" // lint:allow-string
            case .existing(let usage): return usage.id.uuidString
            }
        }
    }

    public init(viewModel: CategoriesViewModel) { self.viewModel = viewModel }

    public var body: some View {
        List {
            Section("categories.custom") {
                if viewModel.categories.isEmpty {
                    Text("categories.empty").foregroundStyle(DSColor.textSecondary)
                }
                ForEach(Array(viewModel.categories.enumerated()), id: \.element.id) { index, usage in
                    Button { editing = .existing(usage) } label: {
                        HStack {
                            Label { Text(verbatim: usage.category.name) } icon: { Image(systemName: "tag") }
                                .foregroundStyle(DSColor.textPrimary)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(usage.category.costGroup.titleKey).font(DSTypography.callout).foregroundStyle(DSColor.textPrimary)
                                Text("categories.usage \(usage.liveExpenseCount)").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                            }
                        }
                        .frame(minHeight: DSSpacing.minTouch)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("category_row_\(index)")
                }
            }
            Section("categories.builtIn") {
                ForEach(ExpenseCategory.allCases.filter { $0 != .custom }, id: \.self) { category in
                    HStack {
                        Label { Text(category.titleKey) } icon: { Image(systemName: category.systemImage) }
                        Spacer()
                        if let group = category.defaultCostGroup {
                            Text(group.titleKey).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                        }
                    }
                    .frame(minHeight: DSSpacing.minTouch)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .accessibilityIdentifier("categories_list")
        .navigationTitle("categories.title")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = .new } label: { Image(systemName: "plus").accessibilityLabel(Text("categories.add")) }
                    .accessibilityIdentifier("categories_add")
            }
        }
        .task { await viewModel.start() }
        .sheet(item: $editing) { target in
            switch target {
            case .new:
                CategoryEditSheet(usage: nil, onSave: { name, group in
                    let key = await viewModel.create(name: name, group: group)
                    if key == nil { editing = nil }
                    return key
                }, onDelete: nil, onCancel: { editing = nil })
            case .existing(let usage):
                CategoryEditSheet(usage: usage, onSave: { name, group in
                    let key = await viewModel.update(usage.id, name: name, group: group)
                    if key == nil { editing = nil }
                    return key
                }, onDelete: {
                    let key = await viewModel.delete(usage.id)
                    if key == nil { editing = nil }
                    return key
                }, onCancel: { editing = nil })
            }
        }
        .alert(viewModel.alertKey ?? "error.generic",
               isPresented: Binding(get: { viewModel.alertKey != nil }, set: { if !$0 { viewModel.alertKey = nil } })) {
            Button("sheet.ok") {}
        }
    }
}
