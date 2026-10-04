import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct ProjectDetailView: View {
    /// A write chosen in a sheet; it runs from the sheet's `onDismiss` so follow-up dialogs and error alerts
    /// present only after the sheet is gone.
    private enum PendingWrite { case status(ProjectStatus), progress(Int?), customer(UUID) }

    @Bindable private var viewModel: ProjectDetailViewModel
    private let makeCustomer: (UUID) -> AnyView
    private let makeActivity: (UUID) -> AnyView
    private let makeExpensesSection: (UUID) -> AnyView
    private let makeLabourSection: (UUID) -> AnyView
    private let makePaymentForm: (PaymentFormRequest) -> AnyView
    @State private var paymentRequest: PaymentFormRequest?
    @State private var editWizard: ProjectWizardViewModel?
    @State private var showStatusPicker = false
    @State private var showProgress = false
    @State private var showCustomerPicker = false
    @State private var pendingWrite: PendingWrite?
    @State private var pendingStatus: ProjectStatus?
    @State private var confirmStatus = false
    @State private var suggestProgress = false
    @State private var confirmDelete = false
    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: ProjectDetailViewModel, makeCustomer: @escaping (UUID) -> AnyView, makeActivity: @escaping (UUID) -> AnyView,
                makeExpensesSection: @escaping (UUID) -> AnyView = { _ in AnyView(EmptyView()) },
                makeLabourSection: @escaping (UUID) -> AnyView = { _ in AnyView(EmptyView()) },
                makePaymentForm: @escaping (PaymentFormRequest) -> AnyView = { _ in AnyView(EmptyView()) }) {
        self.viewModel = viewModel; self.makeCustomer = makeCustomer; self.makeActivity = makeActivity; self.makeExpensesSection = makeExpensesSection
        self.makeLabourSection = makeLabourSection; self.makePaymentForm = makePaymentForm
    }

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
        .toolbar {
            if viewModel.snapshot != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showCustomerPicker = true } label: { Label("detail.customer.change", systemImage: "person.crop.circle.badge.checkmark") }
                            .accessibilityIdentifier("detail_change_customer_menu")
                        Button(role: .destructive) { confirmDelete = true } label: { Label("detail.delete.title", systemImage: "trash") }
                            .accessibilityIdentifier("detail_delete")
                    } label: {
                        Image(systemName: "ellipsis.circle").accessibilityLabel(Text("detail.menu"))
                    }
                    .accessibilityIdentifier("detail_menu")
                }
            }
        }
        .task { await viewModel.start() }
        .task { await viewModel.startInsights() }
        .task { await viewModel.startActivity() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.update(today: TodayProvider.today(timeZone: timeZone)) }
        }
        .sheet(item: $viewModel.editing) { section in
            if let wizard = editWizard {
                EditSectionSheet(section: section, wizard: wizard, onSave: { w in await viewModel.save(w, section: section) }, onCancel: { viewModel.editing = nil })
            }
        }
        .sheet(item: $paymentRequest) { request in makePaymentForm(request) }
        .sheet(isPresented: $showStatusPicker, onDismiss: runPendingWrite) {
            StatusPickerSheet(current: viewModel.snapshot?.project.status ?? .estimate) { status in
                pendingWrite = .status(status); showStatusPicker = false
            }
        }
        .sheet(isPresented: $showProgress, onDismiss: runPendingWrite) {
            ProgressSheet(initial: viewModel.snapshot?.project.manualProgress,
                          onSave: { value in pendingWrite = .progress(value); showProgress = false },
                          onCancel: { showProgress = false })
        }
        .sheet(isPresented: $showCustomerPicker, onDismiss: runPendingWrite) {
            CustomerPickerSheet(customerRepository: viewModel.customerRepository, companyId: viewModel.companyId,
                                current: viewModel.snapshot?.customer.id ?? UUID()) { id in
                pendingWrite = .customer(id); showCustomerPicker = false
            }
        }
        .confirmationDialog("status.confirm.title", isPresented: $confirmStatus, titleVisibility: .visible, presenting: pendingStatus) { status in
            Button("status.confirm.confirm", role: .destructive) { Task { await apply(status) } }.accessibilityIdentifier("status_confirm")
            Button("sheet.cancel", role: .cancel) {}
        } message: { _ in
            Text("status.confirm.message")
        }
        .alert("status.suggestProgress.title", isPresented: $suggestProgress) {
            Button("status.suggestProgress.yes") { Task { _ = await viewModel.setProgress(100) } }.accessibilityIdentifier("status_progress_yes")
            Button("status.suggestProgress.no", role: .cancel) {}.accessibilityIdentifier("status_progress_no")
        }
        .confirmationDialog("detail.delete.title", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("detail.delete.confirm", role: .destructive) { Task { if await viewModel.deleteProject() { dismiss() } } }.accessibilityIdentifier("detail_delete_confirm")
            Button("sheet.cancel", role: .cancel) {}
        } message: {
            Text("detail.delete.message")
        }
        .alert(viewModel.actionErrorKey ?? "error.generic", isPresented: Binding(get: { viewModel.actionErrorKey != nil }, set: { if !$0 { viewModel.actionErrorKey = nil } })) {
            Button("sheet.ok") {}
        }
        .alert(viewModel.errorKey ?? "detail.error", isPresented: Binding(get: { viewModel.errorKey != nil }, set: { if !$0 { viewModel.errorKey = nil } })) { Button("sheet.ok") {} }
    }

    // MARK: - Actions

    private func edit(_ section: EditSection) {
        guard let wizard = viewModel.makeEditWizard(section) else { return }
        editWizard = wizard
        viewModel.editing = section
    }

    private func runPendingWrite() {
        guard let write = pendingWrite else { return }
        pendingWrite = nil
        Task {
            switch write {
            case .status(let status): await pick(status)
            case .progress(let value): _ = await viewModel.setProgress(value)
            case .customer(let id): _ = await viewModel.changeCustomer(id)
            }
        }
    }

    private func pick(_ status: ProjectStatus) async {
        guard let project = viewModel.snapshot?.project, project.status != status else { return }
        let probe = ProjectStatusChange.apply(project, to: status)
        if probe.requiresConfirmation { pendingStatus = status; confirmStatus = true; return }
        await apply(status)
    }

    private func apply(_ status: ProjectStatus) async {
        if let outcome = await viewModel.changeStatus(status), outcome.suggestProgress100 { suggestProgress = true }
    }

    // MARK: - Content

    @ViewBuilder private func content(_ s: ProjectDetailSnapshot) -> some View {
        let currency = viewModel.currency.rawValue
        let insights = viewModel.insights
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            header(s, insights: insights)

            FinancialSummarySection(insights: insights, currency: viewModel.currency, onEditEstimate: { edit(.estimate($0)) })
            ProjectPaymentsSection(list: viewModel.payments,
                                   onAdd: { paymentRequest = .create(projectId: viewModel.projectId, scheduleItemId: nil) },
                                   onEdit: { paymentRequest = .edit($0) })
            makeExpensesSection(viewModel.projectId)
            makeLabourSection(viewModel.projectId)
            HealthSection(insights: insights)
            TimelineSection(insights: insights, project: s.project, today: viewModel.today, onEdit: { edit(.timeline) }, onAdd: { edit(.timeline) })

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
            section("detail.priceDeposit", .priceDeposit) {
                FormRow("wizard.price.contract") { MoneyText(amount: s.project.contractValue.amount, currencyCode: currency) }
                if let dep = s.scheduleItems.first(where: \.isDeposit) {
                    FormRow("schedule.row.deposit") { MoneyText(amount: dep.amount.amount, currencyCode: currency) }
                    if let due = dep.dueDate { FormRow("wizard.deposit.deadline") { DateLabel(due.noonDate(in: timeZone)) } }
                } else { Text("detail.noDeposit").foregroundStyle(DSColor.textSecondary) }
                if s.project.depositRequiredToStart { Text("wizard.deposit.blocksStart").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
            }
            scheduleSection(s, insights: insights)
            customerCard(s)
            ActivitySection(entries: viewModel.activity, currency: viewModel.currency) { makeActivity(viewModel.projectId) }
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    @ViewBuilder private func header(_ s: ProjectDetailSnapshot, insights: ProjectInsights?) -> some View {
        let progress = insights?.progress ?? ProgressCalculator.percent(tasks: [], manualProgress: s.project.manualProgress)
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text(verbatim: s.project.address.line).font(DSTypography.headline)
                        if let city = s.project.address.city { Text(verbatim: city).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
                        Text(verbatim: s.customer.name).font(DSTypography.callout).foregroundStyle(DSColor.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: DSSpacing.xs) {
                        Button { showStatusPicker = true } label: {
                            HStack(spacing: DSSpacing.xs) {
                                StatusBadge(s.project.status.titleKey, tone: s.project.status.tone)
                                Image(systemName: "chevron.down").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("detail_status")
                        if let h = insights?.health {
                            HealthChip(h.status.titleKey, tone: h.status.tone)
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("detail_health")
                        }
                    }
                }
                Button { showProgress = true } label: {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        HStack {
                            Text("progress.title").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                            Spacer()
                            Text(verbatim: "\(progress)%").font(DSTypography.money(.caption)).foregroundStyle(DSColor.textPrimary)
                        }
                        ProgressBar(progress: progress, tone: s.project.status.tone)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("detail_progress")
                FormRow("home.contractValue") { MoneyText(amount: s.project.contractValue.amount, currencyCode: viewModel.currency.rawValue, style: .headline) }
                if let start = s.project.startDate, let end = s.project.estimatedCompletionDate {
                    HStack(spacing: DSSpacing.xs) {
                        DateLabel(start.noonDate(in: timeZone))
                        Text(verbatim: "→")
                        DateLabel(end.noonDate(in: timeZone))
                    }
                    .font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("detail_header")
    }

    @ViewBuilder private func scheduleSection(_ s: ProjectDetailSnapshot, insights: ProjectInsights?) -> some View {
        let currency = viewModel.currency
        let byItem = Dictionary((insights?.payments ?? []).map { ($0.item.id, $0) }, uniquingKeysWith: { a, _ in a })
        section("detail.schedule", .schedule) {
            ForEach(s.scheduleItems) { item in
                let insight = byItem[item.id]
                let status = insight?.status ?? PaymentStatusResolver.status(item: item, paidForItem: .zero(currency), today: viewModel.today)
                Button { paymentRequest = .create(projectId: viewModel.projectId, scheduleItemId: item.id) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            RowLabel.text(item.label).font(DSTypography.callout)
                            if let due = item.dueDate { DateLabel(due.noonDate(in: timeZone)).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
                            if let insight, insight.paid.amount > 0 {
                                let paid = MoneyFormat.string(insight.paid.amount, currencyCode: currency.rawValue, locale: locale)
                                let left = MoneyFormat.string(insight.remaining.amount, currencyCode: currency.rawValue, locale: locale)
                                Text("detail.schedule.paid \(paid) \(left)").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                            }
                        }
                        Spacer()
                        StatusBadge(status.titleKey, tone: status.tone)
                        MoneyText(amount: item.amount.amount, currencyCode: currency.rawValue)
                        Image(systemName: "chevron.right").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                    }
                    .foregroundStyle(DSColor.textPrimary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint(Text("detail.payments.add"))
                .accessibilityIdentifier("detail_schedule_row_\(item.sortOrder)")
            }
            if s.scheduleItems.isEmpty { Text("detail.empty").foregroundStyle(DSColor.textSecondary) }
            FormRow("wizard.schedule.total") {
                MoneyText(amount: ((try? Money.sum(s.scheduleItems.map(\.amount), currency: currency)) ?? .zero(currency)).amount, currencyCode: currency.rawValue, style: .headline)
                    .accessibilityIdentifier("detail_schedule_total")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail_schedule")
    }

    private func customerCard(_ s: ProjectDetailSnapshot) -> some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Text("detail.customer.title").font(DSTypography.headline); Spacer()
                    Button("detail.customer.change") { showCustomerPicker = true }.font(DSTypography.callout).accessibilityIdentifier("detail_change_customer")
                }
                NavigationLink { makeCustomer(s.customer.id) } label: {
                    Label { Text(verbatim: s.customer.name) } icon: { Image(systemName: "person") }.font(DSTypography.callout)
                }
                .accessibilityIdentifier("detail_customer_link")
                if let phone = s.customer.phone { Text(verbatim: phone).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail_customer")
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
}
