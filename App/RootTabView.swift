import SwiftUI
import Domain
import DesignSystem
import FeatureSupport
import HomeFeature
import ProjectsFeature
import CalendarFeature
import ExpensesFeature
import MoreFeature

struct RootTabView: View {
    let ready: AppContainer.Ready
    let setup: CompanySetup
    let settings: AppSettings

    var body: some View {
        TabView {
            NavigationStack { HomeView(viewModel: HomeViewModel(projectRepository: ready.projectRepository, companyId: setup.company.id)) }
                .tabItem { Label("tab.home", systemImage: "house") }
                .accessibilityIdentifier("tab_home")
            NavigationStack { ProjectsPlaceholderView() }
                .tabItem { Label("tab.projects", systemImage: "folder") }
                .accessibilityIdentifier("tab_projects")
            NavigationStack { CalendarPlaceholderView() }
                .tabItem { Label("tab.calendar", systemImage: "calendar") }
                .accessibilityIdentifier("tab_calendar")
            NavigationStack { ExpensesPlaceholderView() }
                .tabItem { Label("tab.expenses", systemImage: "receipt") }
                .accessibilityIdentifier("tab_expenses")
            NavigationStack { MoreView(settings: settings, company: setup.company, showsGallery: showsGallery) }
                .tabItem { Label("tab.more", systemImage: "ellipsis.circle") }
                .accessibilityIdentifier("tab_more")
        }
        .tint(DSColor.accent)
    }

    private var showsGallery: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
