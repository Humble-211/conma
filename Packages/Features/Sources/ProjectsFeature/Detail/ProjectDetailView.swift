import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct ProjectDetailView: View {
    @Bindable private var viewModel: ProjectDetailViewModel
    private let makeCustomer: (UUID) -> AnyView
    @State private var editWizard: ProjectWizardViewModel?
    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale

    public init(viewModel: ProjectDetailViewModel, makeCustomer: @escaping (UUID) -> AnyView) { self.viewModel = viewModel; self.makeCustomer = makeCustomer }

    public var body: some View {
        Group {
            if let s = viewModel.snapshot {
                ScrollView { content(s).padding(.vertical, DSSpacing.lg) }
            } else if viewModel.isLoaded {
                EmptyState(systemImage: "trash", title: "detail.deleted.title", message: "detail.deleted.message")
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(DSColor.background)
        .navigationTitle(Text(verbatim: viewModel.snapshot?.project.name ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.start() }
        .sheet(item: $viewModel.editing) { section in
            if let wizard = editWizard {
                EditSectionSheet(section: section, wizard: wizard, onSave: { w in await viewModel.save(w, section: section) }, onCancel: { viewModel.editing = nil })
            }
        }
        .alert(viewModel.errorKey ?? "detail.error", isPresented: Binding(get: { viewModel.errorKey != nil }, set: { if !$0 { viewModel.errorKey = nil } })) { Button("sheet.ok") {} }
    }

    private func edit(_ section: EditSection) {
        guard let wizard = viewModel.makeEditWizard(section) else { return }
        editWizard = wizard
        viewModel.editing = section
    }

    @ViewBuilder private func content(_ s: ProjectDetailSnapshot) -> some View {
        let currency = viewModel.currency.rawValue
        let today = CalendarDate(Date(), timeZone: timeZone)
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            Card {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: DSSpacing.xs) {
                            Text(verbatim: s.project.address.line).font(DSTypography.headline)
                            if let city = s.project.address.city { Text(verbatim: city).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
                            NavigationLink { makeCustomer(s.customer.id) } label: {
                                Label { Text(verbatim: s.customer.name) } icon: { Image(systemName: "person") }.font(DSTypography.callout)
                            }
                        }
                        Spacer()
                        StatusBadge(s.project.status.titleKey, tone: s.project.status.tone)
                    }
                    ProgressBar(progress: ProgressCalculator.percent(tasks: [], manualProgress: s.project.manualProgress), tone: s.project.status.tone)
                    FormRow("home.contractValue") { MoneyText(amount: s.project.contractValue.amount, currencyCode: currency, style: .headline) }
                    if let start = s.project.startDate, let end = s.project.estimatedCompletionDate {
                        Text(verbatim: "\(start.storageString) → \(end.storageString)").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                    }
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("detail_header")

            section("detail.scope", .scope) {
                if let d = s.project.scopeDescription { Text(verbatim: d) }
                ForEach(s.project.scopeFields) { f in
                    HStack {
                        if let key = ScopeFieldCatalog.labelKey(forFieldKey: f.fieldKey) { Text(key) } else { Text(verbatim: ScopeFieldCatalog.customLabel(f.fieldKey)) }
                        Spacer(); Text(verbatim: f.valueText).foregroundStyle(DSColor.textSecondary)
                    }.font(DSTypography.callout)
                }
                if s.project.scopeDescription == nil && s.project.scopeFields.isEmpty { Text("detail.empty").foregroundStyle(DSColor.textSecondary) }
            }
            section("detail.timeline", .timeline) {
                if let start = s.project.startDate { FormRow("wizard.timeline.start") { Text(verbatim: start.storageString) } }
                if let end = s.project.estimatedCompletionDate { FormRow("wizard.timeline.end") { Text(verbatim: end.storageString) } }
                if let d = s.project.workingDays { FormRow("wizard.timeline.workingDays") { Text(verbatim: "\(d)") } }
                if s.project.startDate == nil && s.project.estimatedCompletionDate == nil { Text("detail.empty").foregroundStyle(DSColor.textSecondary) }
            }
            estimateSection(s)
            section("detail.priceDeposit", .priceDeposit) {
                FormRow("wizard.price.contract") { MoneyText(amount: s.project.contractValue.amount, currencyCode: currency) }
                if let dep = s.scheduleItems.first(where: \.isDeposit) {
                    FormRow("schedule.row.deposit") { MoneyText(amount: dep.amount.amount, currencyCode: currency) }
                    if let due = dep.dueDate { FormRow("wizard.deposit.deadline") { Text(verbatim: due.storageString) } }
                } else { Text("detail.noDeposit").foregroundStyle(DSColor.textSecondary) }
                if s.project.depositRequiredToStart { Text("wizard.deposit.blocksStart").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
            }
            section("detail.schedule", .schedule) {
                ForEach(s.scheduleItems) { item in
                    let status = PaymentStatusResolver.status(item: item, paidForItem: .zero(viewModel.currency), today: today)
                    HStack {
                        VStack(alignment: .leading) {
                            RowLabel.text(item.label).font(DSTypography.callout)
                            if let due = item.dueDate { Text(verbatim: due.storageString).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
                        }
                        Spacer()
                        StatusBadge(LocalizedStringKey("payment.status." + status.rawValue), tone: Self.tone(status))
                        MoneyText(amount: item.amount.amount, currencyCode: currency)
                    }
                }
                if s.scheduleItems.isEmpty { Text("detail.empty").foregroundStyle(DSColor.textSecondary) }
                FormRow("wizard.schedule.total") {
                    MoneyText(amount: ((try? Money.sum(s.scheduleItems.map(\.amount), currency: viewModel.currency)) ?? .zero(viewModel.currency)).amount, currencyCode: currency, style: .headline)
                        .accessibilityIdentifier("detail_schedule_total")
                }
            }
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    @ViewBuilder private func estimateSection(_ s: ProjectDetailSnapshot) -> some View {
        let currency = viewModel.currency
        let f = (try? FinancialCalculator.compute(FinancialInputs(project: s.project, estimateLines: s.estimateLines, expenses: [], labourEntries: [], payments: [], approvedChangeOrders: .zero(currency))))
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text("detail.estimate").font(DSTypography.headline)
                ForEach([CostGroup.labour, .material], id: \.self) { group in
                    HStack {
                        Text(LocalizedStringKey("costGroup." + group.rawValue))
                        Spacer()
                        MoneyText(amount: f?.estimateByGroup[group]?.amount ?? 0, currencyCode: currency.rawValue)
                        Button("wizard.review.edit") { edit(.estimate(group)) }.font(DSTypography.callout).accessibilityIdentifier("detail_edit_estimate_" + group.rawValue)
                    }
                }
                HStack {
                    Text("wizard.step.otherCosts"); Spacer()
                    let other = [CostGroup.subcontractor, .equipment, .permit, .other].compactMap { f?.estimateByGroup[$0] }
                    MoneyText(amount: ((try? Money.sum(other, currency: currency)) ?? .zero(currency)).amount, currencyCode: currency.rawValue)
                    Button("wizard.review.edit") { edit(.estimate(.other)) }.font(DSTypography.callout).accessibilityIdentifier("detail_edit_estimate_other")
                }
                Divider()
                FormRow("wizard.price.estimatedCost") { MoneyText(amount: f?.estimatedCost.amount ?? 0, currencyCode: currency.rawValue, style: .headline).accessibilityIdentifier("detail_estimate_total") }
                FormRow("wizard.price.profit") { MoneyText(amount: f?.projectedProfit.amount ?? 0, currencyCode: currency.rawValue) }
                FormRow("wizard.price.margin") { if let m = f?.projectedMargin { Text(verbatim: LocaleNumberParser.string(m.points, locale: locale, fractionDigits: 1) + "%") } else { Text(verbatim: "—") } }
            }
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, _ edit: EditSection, @ViewBuilder content: () -> Content) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Text(title).font(DSTypography.headline); Spacer()
                    Button("wizard.review.edit") { self.edit(edit) }.font(DSTypography.callout).accessibilityIdentifier("detail_edit_" + edit.id)
                }
                content()
            }
        }
    }

    private static func tone(_ status: PaymentStatus) -> DSTone {
        switch status {
        case .paid: return .success
        case .overdue: return .danger
        case .dueToday, .dueSoon, .partiallyPaid: return .warning
        case .upcoming: return .neutral
        }
    }
}
