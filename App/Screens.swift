import SwiftUI
import Domain
import FeatureSupport
import SetupFeature
import HomeFeature
import ProjectsFeature
import CustomersFeature

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
                 makeActivity: { id in AnyView(ActivityScreen(projectId: id, ready: ready, setup: setup)) })
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
                          makeActivity: { id in AnyView(ActivityScreen(projectId: id, ready: ready, setup: setup)) })
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
