import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct HomeView: View {
    private let viewModel: HomeViewModel
    private let companyName: String
    private let makeDetail: (UUID) -> AnyView
    private let makeActivity: (UUID) -> AnyView
    private let makeExpenseForm: ((ExpenseFormRequest) -> AnyView)?
    private let makePaymentForm: ((PaymentFormRequest) -> AnyView)?

    @State private var showAllAttention = false
    @State private var expenseRequest: ExpenseFormRequest?
    @State private var paymentRequest: PaymentFormRequest?
    /// A payment chosen in the all-attention sheet; it opens from that sheet's `onDismiss`.
    @State private var pendingPayment: PaymentFormRequest?
    @State private var pendingDetail: UUID?
    @State private var retryToken = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.timeZone) private var timeZone

    public init(viewModel: HomeViewModel, companyName: String = "", makeDetail: @escaping (UUID) -> AnyView, makeActivity: @escaping (UUID) -> AnyView,
                makeExpenseForm: ((ExpenseFormRequest) -> AnyView)? = nil, makePaymentForm: ((PaymentFormRequest) -> AnyView)? = nil) {
        self.viewModel = viewModel; self.companyName = companyName; self.makeDetail = makeDetail; self.makeActivity = makeActivity
        self.makeExpenseForm = makeExpenseForm; self.makePaymentForm = makePaymentForm
    }

    /// "Record" action for the all-attention sheet; nil hides the button when no payment form is wired.
    private var recordFromSheet: ((AttentionItem) -> Void)? {
        guard makePaymentForm != nil else { return nil }
        return { item in
            guard let itemId = item.scheduleItemId else { return }
            pendingPayment = .create(projectId: item.projectId, scheduleItemId: itemId)
            showAllAttention = false
        }
    }

    private var names: [UUID: String] {
        Dictionary(viewModel.dashboard?.cards.map { ($0.id, $0.project.name) } ?? [], uniquingKeysWith: { a, _ in a })
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if viewModel.errorKey != nil {
                    VStack(spacing: DSSpacing.md) {
                        EmptyState(systemImage: "exclamationmark.triangle", title: "home.error", message: "home.error.message")
                        SecondaryButton("home.retry") { viewModel.retry(); retryToken += 1 }
                            .accessibilityIdentifier("home_retry")
                    }
                } else if let d = viewModel.dashboard {
                    ScrollView { content(d).padding(.vertical, DSSpacing.lg) }
                        .accessibilityIdentifier("home_list")
                } else {
                    ScrollView {
                        VStack(spacing: DSSpacing.md) { SkeletonCard(lines: 2); SkeletonCard(); SkeletonCard() }.padding(DSSpacing.lg)
                    }
                    .accessibilityIdentifier("home_list")
                }
            }
            if makeExpenseForm != nil {
                FloatingActionButton(accessibilityLabel: "home.addExpense") { expenseRequest = .create(projectId: nil) }
                    .padding(DSSpacing.xl)
                    .accessibilityIdentifier("home_add_expense")
            }
        }
        .background(DSColor.background)
        .navigationTitle("home.title")
        .navigationDestination(for: ProjectRoute.self) { route in
            switch route {
            case .detail(let id): makeDetail(id)
            case .activity(let id): makeActivity(id)
            }
        }
        .navigationDestination(item: $pendingDetail) { id in makeDetail(id) }
        .task(id: retryToken) {
            viewModel.update(today: TodayProvider.today(timeZone: timeZone))
            await viewModel.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.update(today: TodayProvider.today(timeZone: timeZone)) }
        }
        .sheet(isPresented: $showAllAttention, onDismiss: {
            if let next = pendingPayment { pendingPayment = nil; paymentRequest = next }
        }) {
            AttentionListSheet(items: viewModel.dashboard?.attention ?? [], names: names,
                               onSelect: { id in showAllAttention = false; pendingDetail = id },
                               onRecord: recordFromSheet)
        }
        .sheet(item: $paymentRequest) { request in makePaymentForm?(request) ?? AnyView(EmptyView()) }
        .fullScreenCover(item: $expenseRequest) { request in makeExpenseForm?(request) ?? AnyView(EmptyView()) }
    }

    @ViewBuilder private func content(_ d: Dashboard) -> some View {
        let names = self.names
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(verbatim: companyName).font(DSTypography.title)
                DateLabel(viewModel.today.noonDate(in: timeZone), style: .full)
                    .font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                    .accessibilityIdentifier("home_date")
            }
            .padding(.horizontal, DSSpacing.lg)

            Card {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Text("home.attention.title").font(DSTypography.headline)
                    if d.attention.isEmpty {
                        Label("home.attention.empty", systemImage: "checkmark.circle")
                            .foregroundStyle(DSColor.success).accessibilityIdentifier("home_attention_empty")
                    } else {
                        ForEach(d.attention.prefix(5)) { item in
                            HStack(spacing: DSSpacing.sm) {
                                NavigationLink(value: ProjectRoute.detail(item.projectId)) {
                                    AttentionRow(item: item, projectName: names[item.projectId] ?? "")
                                }
                                .buttonStyle(.plain)
                                if makePaymentForm != nil, let itemId = item.scheduleItemId {
                                    Button { paymentRequest = .create(projectId: item.projectId, scheduleItemId: itemId) } label: {
                                        Text("attention.record").font(DSTypography.callout)
                                    }
                                    .buttonStyle(.bordered)
                                    .frame(minHeight: DSSpacing.minTouch)
                                    .accessibilityIdentifier("attention_record_\(itemId.uuidString)")
                                }
                            }
                        }
                        if d.attention.count > 5 {
                            Button("home.attention.more \(d.attention.count)") { showAllAttention = true }
                                .accessibilityIdentifier("home_attention_more")
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain).accessibilityIdentifier("home_attention")
            .padding(.horizontal, DSSpacing.lg)

            TotalsCard(totals: d.totals).padding(.horizontal, DSSpacing.lg)

            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                if d.cards.isEmpty {
                    EmptyState(systemImage: "hammer", title: "home.empty.title", message: "home.empty.message")
                } else {
                    ForEach(CardGroup.allCases, id: \.self) { group in
                        let cards = d.cards.filter { $0.group == group }
                        if !cards.isEmpty {
                            SectionHeader(groupKey(group)).padding(.horizontal, DSSpacing.lg)
                            ForEach(cards) { card in
                                NavigationLink(value: ProjectRoute.detail(card.id)) {
                                    ProjectCardView(project: card.project, customerName: card.customerName, insights: card.insights, progress: card.insights.progress)
                                }
                                .buttonStyle(.plain).padding(.horizontal, DSSpacing.lg)
                            }
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home_projects")
        }
        .padding(.bottom, 72)
    }

    private func groupKey(_ group: CardGroup) -> LocalizedStringKey {
        switch group {
        case .inWork: return "home.group.inWork"
        case .preStart: return "home.group.preStart"
        case .workDone: return "home.group.workDone"
        }
    }
}
