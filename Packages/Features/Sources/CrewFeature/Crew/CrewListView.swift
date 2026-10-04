import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// More → Crew: live crew by name; tap to edit, "+" to add (spec §5.4).
public struct CrewListView: View {
    @Bindable var viewModel: CrewListViewModel
    @State private var editing: EditTarget?

    enum EditTarget: Identifiable {
        case new
        case existing(Employee)
        var id: String {
            switch self {
            case .new: return "new" // lint:allow-string
            case .existing(let employee): return employee.id.uuidString
            }
        }
    }

    public init(viewModel: CrewListViewModel) { self.viewModel = viewModel }

    public var body: some View {
        Group {
            if viewModel.isLoaded && viewModel.employees.isEmpty {
                VStack(spacing: DSSpacing.lg) {
                    EmptyState(systemImage: "person.2", title: "crew.empty.title", message: "crew.empty.message")
                    PrimaryButton("crew.add", systemImage: "plus") { editing = .new }
                        .accessibilityIdentifier("crew_empty_add")
                        .padding(.horizontal, DSSpacing.lg)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("crew_empty")
            } else {
                List {
                    ForEach(Array(viewModel.employees.enumerated()), id: \.element.id) { index, employee in
                        Button { editing = .existing(employee) } label: { CrewRowView(employee: employee) }
                            .accessibilityIdentifier("crew_row_\(index)")
                    }
                }
                .accessibilityIdentifier("crew_list")
            }
        }
        .background(DSColor.background)
        .navigationTitle("crew.title")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = .new } label: { Label("crew.add", systemImage: "plus") }.accessibilityIdentifier("crew_add")
            }
        }
        .task { await viewModel.start() }
        .sheet(item: $editing) { target in
            switch target {
            case .new:
                CrewFormSheet(employee: nil, currency: viewModel.currency,
                              onSave: { draft in
                                  let error = await viewModel.create(draft)
                                  if error == nil { editing = nil }
                                  return error
                              },
                              onDelete: nil, onCancel: { editing = nil })
            case .existing(let employee):
                CrewFormSheet(employee: employee, currency: viewModel.currency,
                              onSave: { draft in
                                  let error = await viewModel.update(employee, with: draft)
                                  if error == nil { editing = nil }
                                  return error
                              },
                              onDelete: {
                                  let error = await viewModel.delete(employee.id)
                                  if error == nil { editing = nil }
                                  return error
                              },
                              onCancel: { editing = nil })
            }
        }
        .alert(viewModel.errorKey ?? "crew.error", isPresented: Binding(get: { viewModel.errorKey != nil }, set: { if !$0 { viewModel.errorKey = nil } })) {
            Button("sheet.ok") {}
        }
    }
}

/// Name, trade, "$250.00/day" (or "No daily rate"), "$31.25/h" when set.
struct CrewRowView: View {
    let employee: Employee
    @Environment(\.locale) private var locale

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: employee.name).font(DSTypography.callout).foregroundStyle(DSColor.textPrimary)
                if let trade = employee.trade { Text(verbatim: trade).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let daily = employee.dailyRate {
                    Text("labour.rate.perDay \(money(daily))").font(DSTypography.money(.callout)).foregroundStyle(DSColor.textPrimary)
                } else {
                    Text("crew.noRate").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                }
                if let hourly = employee.hourlyRate {
                    Text("crew.rate.hourly \(money(hourly))").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                }
            }
        }
        .frame(minHeight: DSSpacing.minTouch)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func money(_ m: Money) -> String { MoneyFormat.string(m.amount, currencyCode: m.currency.rawValue, locale: locale) }
}
