import SwiftUI
import Domain
import FeatureSupport
import SetupFeature
import HomeFeature
import ProjectsFeature

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
        _viewModel = State(initialValue: HomeViewModel(projectRepository: ready.projectRepository, companyId: setup.company.id))
        self.ready = ready; self.setup = setup
    }

    var body: some View {
        HomeView(viewModel: viewModel, makeDetail: { id in AnyView(ProjectDetailScreen(projectId: id, ready: ready, setup: setup)) })
    }
}

/// Placeholder until the detail screen lands.
struct ProjectDetailScreen: View {
    let projectId: UUID
    let ready: AppContainer.Ready
    let setup: CompanySetup

    var body: some View { Text(verbatim: projectId.uuidString) }
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
                         makeDetail: { id in AnyView(ProjectDetailScreen(projectId: id, ready: ready, setup: setup)) })
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
