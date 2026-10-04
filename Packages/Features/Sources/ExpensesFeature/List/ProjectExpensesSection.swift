import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// Project detail: five newest expenses, "+", "See all" (the same list filtered to the project).
public struct ProjectExpensesSection: View {
    private let viewModel: ExpensesListViewModel
    private let makeAll: () -> AnyView
    private let makeForm: (ExpenseFormRequest) -> AnyView
    @State private var formRequest: ExpenseFormRequest?

    public init(viewModel: ExpensesListViewModel, makeAll: @escaping () -> AnyView, makeForm: @escaping (ExpenseFormRequest) -> AnyView) {
        self.viewModel = viewModel; self.makeAll = makeAll; self.makeForm = makeForm
    }

    public var body: some View {
        let rows = Array((viewModel.list?.rows ?? []).prefix(5))
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Text("detail.expenses.title").font(DSTypography.headline)
                    Spacer()
                    Button { formRequest = .create(projectId: viewModel.filter.projectId) } label: { Label("detail.expenses.add", systemImage: "plus") }
                        .font(DSTypography.callout)
                        .frame(minHeight: DSSpacing.minTouch)
                        .accessibilityIdentifier("detail_expenses_add")
                }
                if rows.isEmpty {
                    Text("detail.expenses.empty")
                        .font(DSTypography.callout)
                        .foregroundStyle(DSColor.textSecondary)
                        .accessibilityIdentifier("detail_expenses_empty")
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Button { formRequest = .edit(row.id) } label: { ExpenseRowView(row: row) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("detail_expense_row_\(index)")
                    }
                    NavigationLink { makeAll() } label: { Text("detail.expenses.all").font(DSTypography.callout) }
                        .frame(minHeight: DSSpacing.minTouch)
                        .accessibilityIdentifier("detail_expenses_all")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail_expenses")
        .task { await viewModel.start() }
        .fullScreenCover(item: $formRequest) { request in makeForm(request) }
    }
}
