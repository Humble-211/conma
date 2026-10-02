import SwiftUI
import Domain
import FeatureSupport
import SetupFeature
import HomeFeature

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

    init(projectRepository: any ProjectRepository, companyId: UUID) {
        _viewModel = State(initialValue: HomeViewModel(projectRepository: projectRepository, companyId: companyId))
    }

    var body: some View { HomeView(viewModel: viewModel) }
}
