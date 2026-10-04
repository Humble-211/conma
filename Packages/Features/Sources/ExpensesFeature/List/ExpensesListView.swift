import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// Expenses tab (and "See all" from a project): day sections, month totals, project/category filters, search.
public struct ExpensesListView: View {
    @Bindable var viewModel: ExpensesListViewModel
    let makeForm: (ExpenseFormRequest) -> AnyView
    @State private var formRequest: ExpenseFormRequest?
    @State private var retryToken = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale

    public init(viewModel: ExpensesListViewModel, makeForm: @escaping (ExpenseFormRequest) -> AnyView) {
        self.viewModel = viewModel; self.makeForm = makeForm
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            List {
                Section {
                    HStack(spacing: DSSpacing.md) {
                        SummaryTile("expenses.thisMonth", value: money(viewModel.list?.thisMonth))
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("expenses_total_this_month")
                        SummaryTile("expenses.lastMonth", value: money(viewModel.list?.lastMonth))
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("expenses_total_last_month")
                    }
                    filters
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: DSSpacing.sm, leading: 0, bottom: DSSpacing.sm, trailing: 0))
                if viewModel.errorKey != nil {
                    VStack(spacing: DSSpacing.md) {
                        Text("expenses.error").foregroundStyle(DSColor.textPrimary)
                        SecondaryButton("expenses.retry") { viewModel.retry(); retryToken += 1 }
                            .accessibilityIdentifier("expenses_retry")
                    }
                } else if let list = viewModel.list {
                    if !viewModel.hasAnyExpense {
                        EmptyState(systemImage: "receipt", title: "expenses.empty.title", message: "expenses.empty.message")
                            .listRowBackground(Color.clear)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("expenses_empty")
                    } else if list.sections.isEmpty {
                        Text("expenses.noResults")
                            .foregroundStyle(DSColor.textSecondary)
                            .accessibilityIdentifier("expenses_no_results")
                    }
                    ForEach(list.sections) { section in
                        Section {
                            ForEach(section.rows) { row in
                                Button { formRequest = .edit(row.id) } label: { ExpenseRowView(row: row) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("expense_row_\(row.id.uuidString)")
                            }
                        } header: {
                            HStack {
                                DateLabel(section.day.noonDate(in: timeZone))
                                Spacer()
                                MoneyText(amount: section.total.amount, currencyCode: section.total.currency.rawValue, style: .caption)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("expenses_day_\(section.day.storageString)")
                        }
                    }
                }
                Color.clear.frame(height: 72).listRowBackground(Color.clear)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .searchable(text: $viewModel.filter.query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("expenses.search"))
            FloatingActionButton(accessibilityLabel: "expenses.add") { formRequest = .create(projectId: viewModel.filter.projectId) }
                .padding(DSSpacing.xl)
                .accessibilityIdentifier("expenses_add")
        }
        .background(DSColor.background)
        .navigationTitle("expenses.title")
        .task(id: retryToken) {
            viewModel.update(today: TodayProvider.today(timeZone: timeZone))
            await viewModel.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.update(today: TodayProvider.today(timeZone: timeZone)) }
        }
        .fullScreenCover(item: $formRequest) { request in makeForm(request) }
    }

    private var filters: some View {
        HStack(spacing: DSSpacing.sm) {
            Menu {
                Button("expenses.filter.allProjects") { viewModel.filter.projectId = nil }
                    .accessibilityIdentifier("expenses_filter_project_all")
                ForEach(Array(viewModel.projectOptions.enumerated()), id: \.element.id) { index, project in
                    Button { viewModel.filter.projectId = project.id } label: { Text(verbatim: project.name) }
                        .accessibilityIdentifier("expenses_filter_project_\(index)")
                }
            } label: {
                chip(projectChipText, active: viewModel.filter.projectId != nil)
            }
            .accessibilityIdentifier("expenses_filter_project")
            Menu {
                Button("expenses.filter.allCategories") { viewModel.filter.category = nil }
                    .accessibilityIdentifier("expenses_filter_category_all")
                ForEach(Array(viewModel.categoryOptions.enumerated()), id: \.offset) { index, choice in
                    Button { viewModel.filter.category = choice } label: { choice.title(customName: viewModel.customName(choice)) }
                        .accessibilityIdentifier("expenses_filter_category_\(index)")
                }
            } label: {
                chip(categoryChipText, active: viewModel.filter.category != nil)
            }
            .accessibilityIdentifier("expenses_filter_category")
            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
    }

    private var projectChipText: Text {
        if let id = viewModel.filter.projectId, let name = viewModel.projectName(id) { return Text(verbatim: name) }
        return Text("expenses.filter.allProjects")
    }

    private var categoryChipText: Text {
        if let choice = viewModel.filter.category { return choice.title(customName: viewModel.customName(choice)) }
        return Text("expenses.filter.allCategories")
    }

    private func chip(_ text: Text, active: Bool) -> some View {
        HStack(spacing: DSSpacing.xs) {
            text.lineLimit(1)
            Image(systemName: "chevron.down").font(DSTypography.caption)
        }
        .font(DSTypography.callout.weight(.medium))
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .frame(minHeight: DSSpacing.minTouch)
        .background(active ? DSColor.accent : DSColor.surface, in: Capsule())
        .foregroundStyle(active ? DSColor.onAccent : DSColor.textPrimary)
        .overlay(Capsule().strokeBorder(DSColor.border, lineWidth: active ? 0 : 1))
    }

    private func money(_ value: Money?) -> Text {
        guard let value else { return Text(verbatim: "—") } // lint:allow-string
        return Text(verbatim: MoneyFormat.string(value.amount, currencyCode: value.currency.rawValue, locale: locale))
    }
}
