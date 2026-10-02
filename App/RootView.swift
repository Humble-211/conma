import SwiftUI
import Domain
import DesignSystem
import FeatureSupport
import SetupFeature

struct RootView: View {
    @Bindable var container: AppContainer

    var body: some View {
        Group {
            switch container.state {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(DSColor.background)
            case .failed(let error):
                DatabaseErrorView(error: error, databaseURL: AppContainer.databaseURL) { Task { await container.retry() } }
            case .ready(let ready):
                if let setup = ready.setup {
                    RootTabView(ready: ready, setup: setup, settings: container.settings)
                } else {
                    SetupView(viewModel: SetupViewModel(companyRepository: ready.companyRepository) { container.completeSetup($0) },
                              settings: container.settings)
                }
            }
        }
        .environment(\.locale, container.settings.resolvedLocale)
        .preferredColorScheme(container.settings.colorScheme)
        .task { if case .loading = container.state { await container.load() } }
    }
}
