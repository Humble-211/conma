import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct CustomerFormView: View {
    private let existing: Customer?
    private let companyId: UUID
    private let onSave: (Customer) async -> Bool
    private let onCancel: () -> Void
    @State private var name: String
    @State private var phone: String
    @State private var email: String
    @State private var preferredContact: ContactMethod?
    @State private var companyName: String
    @State private var secondaryContact: String
    @State private var notes: String
    @State private var saving = false

    public init(customer: Customer?, companyId: UUID, onSave: @escaping (Customer) async -> Bool, onCancel: @escaping () -> Void) {
        existing = customer; self.companyId = companyId; self.onSave = onSave; self.onCancel = onCancel
        _name = State(initialValue: customer?.name ?? ""); _phone = State(initialValue: customer?.phone ?? ""); _email = State(initialValue: customer?.email ?? "")
        _preferredContact = State(initialValue: customer?.preferredContact); _companyName = State(initialValue: customer?.companyName ?? "")
        _secondaryContact = State(initialValue: customer?.secondaryContact ?? ""); _notes = State(initialValue: customer?.notes ?? "")
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("customers.form.contact") {
                    TextField("wizard.customer.name", text: $name).textContentType(.name).accessibilityIdentifier("customer_form_name")
                    TextField("wizard.customer.phone", text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                    TextField("wizard.customer.email", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never)
                    Picker("wizard.customer.preferredContact", selection: $preferredContact) {
                        Text("wizard.customer.contact.none").tag(ContactMethod?.none)
                        ForEach(ContactMethod.allCases, id: \.self) { Text(LocalizedStringKey("contact." + $0.rawValue)).tag(ContactMethod?.some($0)) }
                    }
                }
                Section("customers.form.more") {
                    TextField("wizard.customer.company", text: $companyName)
                    TextField("customers.form.secondaryContact", text: $secondaryContact)
                    TextField("customers.form.notes", text: $notes, axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle(existing == nil ? "customers.form.newTitle" : "customers.form.editTitle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("sheet.cancel", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("sheet.save") { Task { await save() } }
                        .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityIdentifier("customer_form_save")
                }
            }
        }
    }

    private func save() async {
        saving = true; defer { saving = false }
        let now = Date()
        func nilIfEmpty(_ s: String) -> String? { s.trimmingCharacters(in: .whitespaces).isEmpty ? nil : s }
        let customer = Customer(id: existing?.id ?? UUID(), companyId: companyId, name: name.trimmingCharacters(in: .whitespaces), phone: nilIfEmpty(phone), email: nilIfEmpty(email),
                                preferredContact: preferredContact, companyName: nilIfEmpty(companyName), secondaryContact: nilIfEmpty(secondaryContact), notes: nilIfEmpty(notes),
                                createdAt: existing?.createdAt ?? now, updatedAt: now, deletedAt: nil)
        _ = await onSave(customer)
    }
}
