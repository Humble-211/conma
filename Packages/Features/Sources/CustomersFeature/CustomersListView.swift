import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct CustomersListView: View {
    @Bindable private var viewModel: CustomersListViewModel
    private let makeProfile: (UUID) -> AnyView
    @State private var showForm = false

    public init(viewModel: CustomersListViewModel, makeProfile: @escaping (UUID) -> AnyView) { self.viewModel = viewModel; self.makeProfile = makeProfile }

    public var body: some View {
        Group {
            if viewModel.isLoaded && viewModel.customers.isEmpty {
                VStack(spacing: DSSpacing.lg) {
                    EmptyState(systemImage: "person.2", title: "customers.empty.title", message: "customers.empty.message")
                    PrimaryButton("customers.add", systemImage: "person.badge.plus") { showForm = true }.padding(.horizontal, DSSpacing.lg)
                }
            } else {
                List(viewModel.visible) { customer in
                    NavigationLink { makeProfile(customer.id) } label: {
                        VStack(alignment: .leading, spacing: DSSpacing.xs) {
                            Text(verbatim: customer.name).font(DSTypography.headline)
                            if let phone = customer.phone { Text(verbatim: phone).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
                        }.frame(minHeight: DSSpacing.minTouch)
                    }
                }
                .listStyle(.plain).accessibilityIdentifier("customers_list")
            }
        }
        .navigationTitle("customers.title")
        .searchable(text: $viewModel.query, prompt: Text("customers.search"))
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showForm = true } label: { Image(systemName: "plus") }.accessibilityIdentifier("customers_add") } }
        .sheet(isPresented: $showForm) {
            CustomerFormView(customer: nil, companyId: viewModel.companyId, onSave: { c in let ok = await viewModel.save(c); if ok { showForm = false }; return ok }, onCancel: { showForm = false })
        }
        .task { await viewModel.start() }
    }
}
