import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// Picks an existing customer for the project (no "new customer" here — that lives in the wizard and More).
struct CustomerPickerSheet: View {
    let customerRepository: any CustomerRepository
    let companyId: UUID
    let current: UUID
    let onPick: (UUID) -> Void
    @State private var customers: [Customer] = []
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                TextField("wizard.customer.search", text: $query)
                    .accessibilityIdentifier("customer_picker_search")
                ForEach(filtered) { customer in
                    Button { onPick(customer.id) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                                Text(verbatim: customer.name).font(DSTypography.headline).foregroundStyle(DSColor.textPrimary)
                                if let phone = customer.phone { Text(verbatim: phone).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
                            }
                            Spacer()
                            if customer.id == current { Image(systemName: "checkmark.circle.fill").foregroundStyle(DSColor.accent) }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("customer_pick_" + customer.id.uuidString)
                }
            }
            .accessibilityIdentifier("customer_picker")
            .navigationTitle("customer.picker.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("sheet.cancel") { dismiss() }.accessibilityIdentifier("sheet_cancel") }
            }
            .task { await observe() }
        }
    }

    private var filtered: [Customer] {
        let q = SearchFold.normalize(query)
        guard !q.isEmpty else { return customers }
        return customers.filter { c in
            [c.name, c.phone ?? "", c.email ?? "", c.companyName ?? ""].contains { SearchFold.normalize($0).contains(q) }
        }
    }

    private func observe() async {
        do { for try await value in customerRepository.observeAll(companyId: companyId) { customers = value } } catch {}
    }
}
