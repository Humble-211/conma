import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct MoreView: View {
    private let settings: AppSettings
    private let company: Company
    private let showsGallery: Bool

    public init(settings: AppSettings, company: Company, showsGallery: Bool) {
        self.settings = settings; self.company = company; self.showsGallery = showsGallery
    }

    public var body: some View {
        List {
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
