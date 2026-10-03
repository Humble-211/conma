import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct CustomerStep: View {
    @Bindable var viewModel: ProjectWizardViewModel
    let customerRepository: any CustomerRepository
    @State private var customers: [Customer] = []
    @State private var query = ""
    @State private var creatingNew = false

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            if creatingNew {
                newCustomerForm
            } else {
                TextField("wizard.customer.search", text: $query)
                    .textFieldStyle(.roundedBorder).padding(.horizontal, DSSpacing.lg)
                    .accessibilityIdentifier("wizard_customer_search")
                SecondaryButton("wizard.customer.new", systemImage: "person.badge.plus") {
                    creatingNew = true
                    viewModel.draft.customer = .new(NewCustomerInput(name: "", phone: nil, email: nil, preferredContact: nil, companyName: nil, secondaryContact: nil, notes: nil))
                }
                .padding(.horizontal, DSSpacing.lg)
                .accessibilityIdentifier("wizard_new_customer")
                VStack(spacing: DSSpacing.sm) {
                    ForEach(filtered) { customer in
                        let selected = viewModel.draft.customer == .existing(customer.id)
                        Button { viewModel.draft.customer = .existing(customer.id) } label: {
                            Card {
                                HStack {
                                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                                        Text(verbatim: customer.name).font(DSTypography.headline).foregroundStyle(DSColor.textPrimary)
                                        if let phone = customer.phone { Text(verbatim: phone).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
                                    }
                                    Spacer()
                                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(DSColor.accent) }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DSSpacing.lg)
            }
        }
        .task { await observe() }
        .onAppear { if case .new? = viewModel.draft.customer { creatingNew = true } }
    }

    private var filtered: [Customer] {
        let q = SearchFold.normalize(query)
        guard !q.isEmpty else { return customers }
        return customers.filter { c in
            [c.name, c.phone ?? "", c.email ?? "", c.companyName ?? ""].contains { SearchFold.normalize($0).contains(q) }
        }
    }

    private var newInput: Binding<NewCustomerInput> {
        Binding(get: {
            if case .new(let input)? = viewModel.draft.customer { return input }
            return NewCustomerInput(name: "", phone: nil, email: nil, preferredContact: nil, companyName: nil, secondaryContact: nil, notes: nil)
        }, set: { viewModel.draft.customer = .new($0) })
    }

    private var newCustomerForm: some View {
        Card {
            VStack(spacing: DSSpacing.md) {
                TextField("wizard.customer.name", text: newInput.name).textContentType(.name).frame(minHeight: DSSpacing.minTouch).accessibilityIdentifier("wizard_customer_name")
                Divider()
                TextField("wizard.customer.phone", text: optional(newInput.phone)).keyboardType(.phonePad).textContentType(.telephoneNumber).frame(minHeight: DSSpacing.minTouch)
                Divider()
                TextField("wizard.customer.email", text: optional(newInput.email)).keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never).frame(minHeight: DSSpacing.minTouch)
                Divider()
                FormRow("wizard.customer.preferredContact") {
                    Picker("wizard.customer.preferredContact", selection: newInput.preferredContact) {
                        Text("wizard.customer.contact.none").tag(ContactMethod?.none)
                        ForEach(ContactMethod.allCases, id: \.self) { Text(LocalizedStringKey("contact." + $0.rawValue)).tag(ContactMethod?.some($0)) }
                    }.labelsHidden()
                }
                Divider()
                TextField("wizard.customer.company", text: optional(newInput.companyName)).frame(minHeight: DSSpacing.minTouch)
                SecondaryButton("wizard.customer.pickExisting") { creatingNew = false; viewModel.draft.customer = nil }
            }
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    private func optional(_ binding: Binding<String?>) -> Binding<String> {
        Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    private func observe() async {
        do { for try await value in customerRepository.observeAll(companyId: viewModel.companyId) { customers = value } } catch {}
    }
}
