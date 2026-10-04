import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct MoreView: View {
    private let settings: AppSettings
    private let company: Company
    private let showsGallery: Bool

    private let makeCustomers: () -> AnyView
    private let makeCategories: () -> AnyView

    public init(settings: AppSettings, company: Company, showsGallery: Bool, makeCustomers: @escaping () -> AnyView, makeCategories: @escaping () -> AnyView) {
        self.settings = settings; self.company = company; self.showsGallery = showsGallery; self.makeCustomers = makeCustomers; self.makeCategories = makeCategories
    }

    public var body: some View {
        List {
            NavigationLink { makeCustomers() } label: { Label("more.customers", systemImage: "person.2") }
                .frame(minHeight: DSSpacing.minTouch).accessibilityIdentifier("more_customers")
            NavigationLink { makeCategories() } label: { Label("more.categories", systemImage: "tag") }
                .frame(minHeight: DSSpacing.minTouch).accessibilityIdentifier("more_categories")
            NavigationLink { SettingsView(settings: settings, company: company) } label: {
                Label("more.settings", systemImage: "gearshape")
            }
            .frame(minHeight: DSSpacing.minTouch)
            .accessibilityIdentifier("more_settings")
            if showsGallery {
                NavigationLink { ComponentGalleryView() } label: {
                    Label("more.componentGallery", systemImage: "square.grid.2x2")
                }
                .frame(minHeight: DSSpacing.minTouch)
                .accessibilityIdentifier("more_gallery")
            }
        }
        .navigationTitle("more.title")
    }
}
