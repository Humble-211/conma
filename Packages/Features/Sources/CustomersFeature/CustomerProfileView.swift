import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct CustomerProfileView: View {
    private let viewModel: CustomerProfileViewModel
    private let companyId: UUID
    private let onSave: (Customer) async -> Bool
    private let onDelete: () async -> DeleteOutcome
    private let makeProject: (UUID) -> AnyView
    @State private var editing = false
    @State private var deleteOutcome: DeleteOutcome?
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: CustomerProfileViewModel, companyId: UUID, onSave: @escaping (Customer) async -> Bool, onDelete: @escaping () async -> DeleteOutcome, makeProject: @escaping (UUID) -> AnyView) {
        self.viewModel = viewModel; self.companyId = companyId; self.onSave = onSave; self.onDelete = onDelete; self.makeProject = makeProject
    }

    public var body: some View {
        Group {
            if let c = viewModel.customer {
                ScrollView {
                    VStack(alignment: .leading, spacing: DSSpacing.lg) {
                        Card {
                            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                                Text(verbatim: c.name).font(DSTypography.largeTitle)
                                if let company = c.companyName { Text(verbatim: company).foregroundStyle(DSColor.textSecondary) }
                                HStack(spacing: DSSpacing.md) {
                                    if let phone = c.phone {
                                        contactButton("customers.call", "phone.fill", url: "tel:" + phone.filter { !$0.isWhitespace }, id: "customer_call")
                                        contactButton("customers.text", "message.fill", url: "sms:" + phone.filter { !$0.isWhitespace }, id: "customer_text")
                                    }
                                    if let email = c.email { contactButton("customers.email", "envelope.fill", url: "mailto:" + email, id: "customer_email") }
                                }
                                if let phone = c.phone { FormRow("wizard.customer.phone") { Text(verbatim: phone) } }
                                if let email = c.email { FormRow("wizard.customer.email") { Text(verbatim: email) } }
                                if let pref = c.preferredContact { FormRow("wizard.customer.preferredContact") { Text(LocalizedStringKey("contact." + pref.rawValue)) } }
                                if let secondary = c.secondaryContact { FormRow("customers.form.secondaryContact") { Text(verbatim: secondary) } }
                                if let notes = c.notes { Text(verbatim: notes).font(DSTypography.callout).foregroundStyle(DSColor.textSecondary) }
                            }
                        }
                        SectionHeader("customers.projects")
                        if viewModel.projects.isEmpty { Text("customers.noProjects").foregroundStyle(DSColor.textSecondary).padding(.horizontal, DSSpacing.lg) }
                        ForEach(viewModel.projects) { project in
                            NavigationLink { makeProject(project.id) } label: {
                                Card {
                                    HStack {
                                        VStack(alignment: .leading) { Text(verbatim: project.name).font(DSTypography.headline); Text(verbatim: project.address.line).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
                                        Spacer(); StatusBadge(project.status.titleKey, tone: project.status.tone)
                                    }
                                }
                            }.buttonStyle(.plain)
                        }
                    }.padding(DSSpacing.lg)
                }
                .accessibilityIdentifier("customer_profile")
            } else if viewModel.isLoaded {
                EmptyState(systemImage: "person.slash", title: "customers.missing.title", message: "customers.missing.message")
            } else { ProgressView() }
        }
        .background(DSColor.background)
        .navigationTitle(Text(verbatim: viewModel.customer?.name ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("customers.edit") { editing = true }.accessibilityIdentifier("customer_edit")
                    Button("customers.delete", role: .destructive) { Task { deleteOutcome = await onDelete(); if deleteOutcome == .deleted { dismiss() } } }.accessibilityIdentifier("customer_delete")
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityIdentifier("customer_menu")
                .disabled(viewModel.customer == nil)
            }
        }
        .sheet(isPresented: $editing) {
            CustomerFormView(customer: viewModel.customer, companyId: companyId, onSave: { c in let ok = await onSave(c); if ok { editing = false; await viewModel.load() }; return ok }, onCancel: { editing = false })
        }
        .alert("customers.delete.blocked", isPresented: Binding(get: { deleteOutcome == .hasProjects }, set: { if !$0 { deleteOutcome = nil } })) { Button("sheet.ok") {} }
        .alert("customers.saveFailed", isPresented: Binding(get: { deleteOutcome == .failed }, set: { if !$0 { deleteOutcome = nil } })) { Button("sheet.ok") {} }
        .task { await viewModel.load() }
    }

    private func contactButton(_ title: LocalizedStringKey, _ symbol: String, url: String, id: String) -> some View {
        Button { if let u = URL(string: url) { UIApplication.shared.open(u) } } label: {
            Label(title, systemImage: symbol).font(DSTypography.callout).padding(.horizontal, DSSpacing.md).frame(minHeight: DSSpacing.minTouch)
                .background(DSColor.accent.opacity(0.14), in: Capsule()).foregroundStyle(DSColor.accent)
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }
}
