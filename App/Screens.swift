import SwiftUI
import Domain
import FeatureSupport
import SetupFeature
import HomeFeature
import ProjectsFeature
import CustomersFeature
import ExpensesFeature
import PaymentsFeature
import CrewFeature

/// Owns the setup view model so parent re-renders (e.g. language change) don't recreate it.
struct SetupScreen: View {
    @State private var viewModel: SetupViewModel
    let settings: AppSettings

    init(companyRepository: any CompanyRepository, settings: AppSettings, onCompleted: @escaping (CompanySetup) -> Void) {
        _viewModel = State(initialValue: SetupViewModel(companyRepository: companyRepository, onCompleted: onCompleted))
        self.settings = settings
    }

    var body: some View { SetupView(viewModel: viewModel, settings: settings) }
}

/// Owns the home view model so parent re-renders don't restart observation.
struct HomeScreen: View {
    @State private var viewModel: HomeViewModel

    let ready: AppContainer.Ready
    let setup: CompanySetup

    init(ready: AppContainer.Ready, setup: CompanySetup) {
        _viewModel = State(initialValue: HomeViewModel(insightsRepository: ready.insightsRepository, companyId: setup.company.id, today: TodayProvider.today(timeZone: .current)))
        self.ready = ready; self.setup = setup
    }

    var body: some View {
        HomeView(viewModel: viewModel, companyName: setup.company.name,
                 makeDetail: { id in AnyView(ProjectDetailScreen(projectId: id, ready: ready, setup: setup)) },
                 makeActivity: { id in AnyView(ActivityScreen(projectId: id, ready: ready, setup: setup)) },
                 makeExpenseForm: { request in AnyView(ExpenseFlowScreen(request: request, ready: ready, setup: setup)) },
                 makePaymentForm: { request in AnyView(PaymentFormScreen(request: request, ready: ready, setup: setup)) })
    }
}

struct ProjectDetailScreen: View {
    @State private var viewModel: ProjectDetailViewModel
    let ready: AppContainer.Ready
    let setup: CompanySetup

    init(projectId: UUID, ready: AppContainer.Ready, setup: CompanySetup) {
        _viewModel = State(initialValue: ProjectDetailViewModel(projectId: projectId, companyId: setup.company.id, currency: setup.company.currencyCode,
                                                                 projectRepository: ready.projectRepository, estimateRepository: ready.estimateRepository,
                                                                 scheduleRepository: ready.scheduleRepository, insightsRepository: ready.insightsRepository,
                                                                 activityLogRepository: ready.activityLogRepository, customerRepository: ready.customerRepository,
                                                                 actor: ActivityActor(userId: setup.owner.id, name: setup.owner.displayName),
                                                                 today: TodayProvider.today(timeZone: .current)))
        self.ready = ready; self.setup = setup
    }

    var body: some View {
        ProjectDetailView(viewModel: viewModel,
                          makeCustomer: { id in AnyView(CustomerProfileScreen(customerId: id, ready: ready, setup: setup)) },
                          makeActivity: { id in AnyView(ActivityScreen(projectId: id, ready: ready, setup: setup)) },
                          makeExpensesSection: { id in AnyView(ProjectExpensesSectionScreen(projectId: id, ready: ready, setup: setup)) },
                          makeLabourSection: { id in AnyView(ProjectLabourSectionScreen(projectId: id, ready: ready, setup: setup)) },
                          makePaymentForm: { request in AnyView(PaymentFormScreen(request: request, ready: ready, setup: setup)) })
    }
}

/// Owns the full activity list view model for one project.
struct ActivityScreen: View {
    @State private var viewModel: ActivityListViewModel

    init(projectId: UUID, ready: AppContainer.Ready, setup: CompanySetup) {
        _viewModel = State(initialValue: ActivityListViewModel(projectId: projectId, currency: setup.company.currencyCode, activityLogRepository: ready.activityLogRepository))
    }

    var body: some View { ActivityListView(viewModel: viewModel) }
}

struct CustomersScreen: View {
    @State private var viewModel: CustomersListViewModel
    let ready: AppContainer.Ready
    let setup: CompanySetup

    init(ready: AppContainer.Ready, setup: CompanySetup) {
        _viewModel = State(initialValue: CustomersListViewModel(customerRepository: ready.customerRepository, companyId: setup.company.id, actor: ActivityActor(userId: setup.owner.id, name: setup.owner.displayName)))
        self.ready = ready; self.setup = setup
    }

    var body: some View { CustomersListView(viewModel: viewModel, makeProfile: { id in AnyView(CustomerProfileScreen(customerId: id, ready: ready, setup: setup)) }) }
}

struct CustomerProfileScreen: View {
    @State private var viewModel: CustomerProfileViewModel
    @State private var listViewModel: CustomersListViewModel
    let ready: AppContainer.Ready
    let setup: CompanySetup

    init(customerId: UUID, ready: AppContainer.Ready, setup: CompanySetup) {
        _viewModel = State(initialValue: CustomerProfileViewModel(customerId: customerId, customerRepository: ready.customerRepository))
        _listViewModel = State(initialValue: CustomersListViewModel(customerRepository: ready.customerRepository, companyId: setup.company.id, actor: ActivityActor(userId: setup.owner.id, name: setup.owner.displayName)))
        self.ready = ready; self.setup = setup
    }

    var body: some View {
        CustomerProfileView(viewModel: viewModel, companyId: setup.company.id,
                            onSave: { await listViewModel.save($0) },
                            onDelete: { await listViewModel.delete(viewModel.customer?.id ?? UUID()) },
                            makeProject: { id in AnyView(ProjectDetailScreen(projectId: id, ready: ready, setup: setup)) })
    }
}

/// Owns the list view model; builds wizard/detail screens with Data-backed repositories.
struct ProjectsScreen: View {
    @State private var viewModel: ProjectsListViewModel
    let ready: AppContainer.Ready
    let setup: CompanySetup

    init(ready: AppContainer.Ready, setup: CompanySetup) {
        _viewModel = State(initialValue: ProjectsListViewModel(projectRepository: ready.projectRepository, draftStore: ready.draftStore, companyId: setup.company.id))
        self.ready = ready; self.setup = setup
    }

    var body: some View {
        ProjectsListView(viewModel: viewModel,
                         makeWizard: { draft, onCreated, onDismiss in AnyView(WizardScreen(draft: draft, ready: ready, setup: setup, onCreated: onCreated, onDismiss: onDismiss)) },
                         makeDetail: { id in AnyView(ProjectDetailScreen(projectId: id, ready: ready, setup: setup)) },
                         makeActivity: { id in AnyView(ActivityScreen(projectId: id, ready: ready, setup: setup)) })
    }
}

struct WizardScreen: View {
    @State private var viewModel: ProjectWizardViewModel
    let customerRepository: any CustomerRepository

    init(draft: ProjectDraft, ready: AppContainer.Ready, setup: CompanySetup, onCreated: @escaping (UUID) -> Void, onDismiss: @escaping () -> Void) {
        _viewModel = State(initialValue: ProjectWizardViewModel(draft: draft, companyId: setup.company.id, currency: setup.company.currencyCode,
                                                                 projectRepository: ready.projectRepository, draftStore: ready.draftStore,
                                                                 actor: ActivityActor(userId: setup.owner.id, name: setup.owner.displayName),
                                                                 onCreated: onCreated, onDismiss: onDismiss))
        self.customerRepository = ready.customerRepository
    }

    var body: some View { ProjectWizardView(viewModel: viewModel, customerRepository: customerRepository) }
}

/// Expenses tab (projectId nil) or a project's "See all" (filtered; the filter can be cleared).
struct ExpensesScreen: View {
    @State private var viewModel: ExpensesListViewModel
    let ready: AppContainer.Ready
    let setup: CompanySetup

    init(projectId: UUID? = nil, ready: AppContainer.Ready, setup: CompanySetup) {
        _viewModel = State(initialValue: ExpensesListViewModel(expenseRepository: ready.expenseRepository, companyId: setup.company.id, currency: setup.company.currencyCode,
                                                               today: TodayProvider.today(timeZone: .current), projectId: projectId))
        self.ready = ready; self.setup = setup
    }

    var body: some View {
        ExpensesListView(viewModel: viewModel, makeForm: { request in AnyView(ExpenseFlowScreen(request: request, ready: ready, setup: setup)) })
    }
}

/// Owns the expense form view model for one create/edit flow; closes with `dismiss` (it is presented full screen).
struct ExpenseFlowScreen: View {
    @State private var viewModel: ExpenseFormViewModel
    private let captureMode: ReceiptCaptureMode
    @Environment(\.dismiss) private var dismiss

    init(request: ExpenseFormRequest, ready: AppContainer.Ready, setup: CompanySetup) {
        _viewModel = State(initialValue: ExpenseFormViewModel(request: request, companyId: setup.company.id, currency: setup.company.currencyCode,
                                                              expenseRepository: ready.expenseRepository, categoryRepository: ready.categoryRepository,
                                                              actor: ActivityActor(userId: setup.owner.id, name: setup.owner.displayName),
                                                              today: TodayProvider.today(timeZone: .current), defaultTaxPercent: ready.settings.defaultTaxPercent))
        captureMode = ready.captureMode
    }

    var body: some View { ExpenseFlowView(viewModel: viewModel, captureMode: captureMode, onClose: { dismiss() }) }
}

/// Project detail's expenses card (five newest, "+", "See all").
struct ProjectExpensesSectionScreen: View {
    @State private var viewModel: ExpensesListViewModel
    let projectId: UUID
    let ready: AppContainer.Ready
    let setup: CompanySetup

    init(projectId: UUID, ready: AppContainer.Ready, setup: CompanySetup) {
        _viewModel = State(initialValue: ExpensesListViewModel(expenseRepository: ready.expenseRepository, companyId: setup.company.id, currency: setup.company.currencyCode,
                                                               today: TodayProvider.today(timeZone: .current), projectId: projectId))
        self.projectId = projectId; self.ready = ready; self.setup = setup
    }

    var body: some View {
        ProjectExpensesSection(viewModel: viewModel,
                               makeAll: { AnyView(ExpensesScreen(projectId: projectId, ready: ready, setup: setup)) },
                               makeForm: { request in AnyView(ExpenseFlowScreen(request: request, ready: ready, setup: setup)) })
    }
}

struct CategoriesScreen: View {
    @State private var viewModel: CategoriesViewModel

    init(ready: AppContainer.Ready, setup: CompanySetup) {
        _viewModel = State(initialValue: CategoriesViewModel(categoryRepository: ready.categoryRepository, companyId: setup.company.id))
    }

    var body: some View { CategoriesView(viewModel: viewModel) }
}

/// Owns the payment form view model for one create/edit; closes with `dismiss` (presented as a sheet).
struct PaymentFormScreen: View {
    @State private var viewModel: PaymentFormViewModel
    @Environment(\.dismiss) private var dismiss

    init(request: PaymentFormRequest, ready: AppContainer.Ready, setup: CompanySetup) {
        _viewModel = State(initialValue: PaymentFormViewModel(request: request, companyId: setup.company.id, currency: setup.company.currencyCode,
                                                              paymentRepository: ready.paymentRepository, insightsRepository: ready.insightsRepository,
                                                              actor: ActivityActor(userId: setup.owner.id, name: setup.owner.displayName),
                                                              today: TodayProvider.today(timeZone: .current)))
    }

    var body: some View { PaymentFormView(viewModel: viewModel, onClose: { dismiss() }) }
}

struct CrewScreen: View {
    @State private var viewModel: CrewListViewModel

    init(ready: AppContainer.Ready, setup: CompanySetup) {
        _viewModel = State(initialValue: CrewListViewModel(employeeRepository: ready.employeeRepository, companyId: setup.company.id, currency: setup.company.currencyCode))
    }

    var body: some View { CrewListView(viewModel: viewModel) }
}

struct LabourFormScreen: View {
    @State private var viewModel: LabourFormViewModel
    @Environment(\.dismiss) private var dismiss

    init(request: LabourFormRequest, ready: AppContainer.Ready, setup: CompanySetup) {
        _viewModel = State(initialValue: LabourFormViewModel(request: request, companyId: setup.company.id, currency: setup.company.currencyCode,
                                                             labourRepository: ready.labourRepository, employeeRepository: ready.employeeRepository,
                                                             actor: ActivityActor(userId: setup.owner.id, name: setup.owner.displayName),
                                                             today: TodayProvider.today(timeZone: .current)))
    }

    var body: some View { LabourFormView(viewModel: viewModel, onClose: { dismiss() }) }
}

/// Project detail's Labour card (three latest days, "Log labour", "See all").
struct ProjectLabourSectionScreen: View {
    @State private var viewModel: ProjectLabourViewModel
    let projectId: UUID
    let ready: AppContainer.Ready
    let setup: CompanySetup

    init(projectId: UUID, ready: AppContainer.Ready, setup: CompanySetup) {
        _viewModel = State(initialValue: ProjectLabourViewModel(labourRepository: ready.labourRepository, projectId: projectId))
        self.projectId = projectId; self.ready = ready; self.setup = setup
    }

    var body: some View {
        ProjectLabourSection(viewModel: viewModel,
                             makeAll: { AnyView(ProjectLabourListScreen(projectId: projectId, ready: ready, setup: setup)) },
                             makeForm: { request in AnyView(LabourFormScreen(request: request, ready: ready, setup: setup)) })
    }
}

struct ProjectLabourListScreen: View {
    @State private var viewModel: ProjectLabourViewModel
    let ready: AppContainer.Ready
    let setup: CompanySetup

    init(projectId: UUID, ready: AppContainer.Ready, setup: CompanySetup) {
        _viewModel = State(initialValue: ProjectLabourViewModel(labourRepository: ready.labourRepository, projectId: projectId))
        self.ready = ready; self.setup = setup
    }

    var body: some View {
        ProjectLabourListView(viewModel: viewModel, makeForm: { request in AnyView(LabourFormScreen(request: request, ready: ready, setup: setup)) })
    }
}
