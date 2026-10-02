import SwiftUI

public struct ComponentGalleryView: View {
    @State private var progress = 65

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                SectionHeader("gallery.buttons")
                VStack(spacing: DSSpacing.md) {
                    PrimaryButton("gallery.primaryButton", systemImage: "plus") {}
                    PrimaryButton("gallery.loadingButton", isLoading: true) {}
                    SecondaryButton("gallery.secondaryButton", systemImage: "camera") {}
                }
                .padding(.horizontal, DSSpacing.lg)

                SectionHeader("gallery.badges")
                HStack(spacing: DSSpacing.sm) {
                    ForEach(DSTone.allCases, id: \.self) { tone in StatusBadge("gallery.badge", tone: tone) }
                }
                .padding(.horizontal, DSSpacing.lg)

                SectionHeader("gallery.progress")
                VStack(spacing: DSSpacing.md) {
                    ProgressBar(progress: progress)
                    ProgressBar(progress: 100, tone: .success)
                    ProgressBar(progress: 20, tone: .danger)
                }
                .padding(.horizontal, DSSpacing.lg)

                SectionHeader("gallery.money")
                HStack(spacing: DSSpacing.md) {
                    SummaryTile("gallery.collected", value: Text(Decimal(20_000), format: .currency(code: "CAD")), tone: .success)
                    SummaryTile("gallery.spent", value: Text(Decimal(19_450), format: .currency(code: "CAD")), tone: .danger)
                }
                .padding(.horizontal, DSSpacing.lg)
                Card {
                    FormRow("gallery.contractValue") { MoneyText(amount: Decimal(string: "38000.00") ?? 0, currencyCode: "CAD") }
                    FormRow("gallery.cashPosition") { MoneyText(amount: Decimal(550), currencyCode: "CAD", style: .headline) }
                }
                .padding(.horizontal, DSSpacing.lg)

                SectionHeader("gallery.emptyState")
                EmptyState(systemImage: "tray", title: "gallery.emptyTitle", message: "gallery.emptyMessage")
                    .frame(height: 220)
            }
            .padding(.vertical, DSSpacing.lg)
        }
        .accessibilityIdentifier("component_gallery")
        .background(DSColor.background)
        .overlay(alignment: .bottomTrailing) {
            FloatingActionButton(accessibilityLabel: "gallery.add") { progress = progress >= 100 ? 0 : progress + 10 }
                .padding(DSSpacing.xl)
        }
        .navigationTitle("gallery.title")
    }
}

#Preview("Light") { NavigationStack { ComponentGalleryView() } }
#Preview("Dark") { NavigationStack { ComponentGalleryView() }.preferredColorScheme(.dark) }
