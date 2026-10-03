import SwiftUI

public struct ComponentGalleryView: View {
    @State private var progress = 65
    /// Fixed instant (2026-10-03 12:00 UTC) so gallery screenshots are deterministic.
    private static let sampleDate = Date(timeIntervalSince1970: 1_791_028_800)

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

                SectionHeader("gallery.health")
                HStack(spacing: DSSpacing.sm) {
                    HealthChip("gallery.badge", tone: .success)
                    HealthChip("gallery.badge", tone: .warning)
                    HealthChip("gallery.badge", tone: .danger)
                }
                .padding(.horizontal, DSSpacing.lg)

                SectionHeader("gallery.dualProgress")
                VStack(spacing: DSSpacing.md) {
                    DualProgressBar(expected: 40, actual: 65, expectedLabel: "gallery.expected", actualLabel: "gallery.actual")
                    DualProgressBar(expected: 80, actual: 30, expectedLabel: "gallery.expected", actualLabel: "gallery.actual")
                    DualProgressBar(expected: nil, actual: 50, expectedLabel: "gallery.expected", actualLabel: "gallery.actual")
                }
                .padding(.horizontal, DSSpacing.lg)

                SectionHeader("gallery.dates")
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    DateLabel(Self.sampleDate)
                    DateLabel(Self.sampleDate, style: .full)
                }
                .padding(.horizontal, DSSpacing.lg)

                SectionHeader("gallery.activity")
                Card {
                    ActivityRow(systemImage: "banknote", title: Text("gallery.activityTitle"), subtitle: Text("gallery.activitySubtitle"))
                    ActivityRow(systemImage: "arrow.triangle.2.circlepath", title: Text("gallery.activityTitle"), subtitle: Text("gallery.activitySubtitle"))
                }
                .padding(.horizontal, DSSpacing.lg)

                SectionHeader("gallery.skeleton")
                SkeletonCard()
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

                SectionHeader("gallery.inputs")
                VStack(spacing: DSSpacing.md) {
                    MoneyField("gallery.contractValue", amount: .constant(Decimal(38_000)), currencyCode: "CAD")
                    DecimalField("gallery.quantity", value: .constant(7.5))
                    IntegerField("gallery.workers", value: .constant(3))
                    ChoiceChips(options: ["a", "b"], selection: .constant("a")) { _ in "gallery.badge" } // lint:allow-string
                    StepHeader(title: "gallery.progress", step: 6, total: 12)
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
