import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// Project detail: labour total, the three latest days, "Log labour", "See all" (spec §5.6).
public struct ProjectLabourSection: View {
    private let viewModel: ProjectLabourViewModel
    private let makeAll: () -> AnyView
    private let makeForm: (LabourFormRequest) -> AnyView
    @State private var formRequest: LabourFormRequest?
    @Environment(\.locale) private var locale

    public init(viewModel: ProjectLabourViewModel, makeAll: @escaping () -> AnyView, makeForm: @escaping (LabourFormRequest) -> AnyView) {
        self.viewModel = viewModel; self.makeAll = makeAll; self.makeForm = makeForm
    }

    public var body: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Text("detail.labour.title").font(DSTypography.headline)
                    Spacer()
                    Button { formRequest = .create(projectId: viewModel.projectId) } label: { Label("detail.labour.add", systemImage: "plus") }
                        .font(DSTypography.callout)
                        .frame(minHeight: DSSpacing.minTouch)
                        .accessibilityIdentifier("detail_labour_add")
                }
                if let list = viewModel.list {
                    if list.sections.isEmpty {
                        Text("detail.labour.empty")
                            .font(DSTypography.callout)
                            .foregroundStyle(DSColor.textSecondary)
                            .accessibilityIdentifier("detail_labour_empty")
                    } else {
                        Text("detail.labour.total \(LabourDays.text(list.totalDays, locale: locale)) \(MoneyFormat.string(list.total.amount, currencyCode: list.total.currency.rawValue, locale: locale))")
                            .font(DSTypography.callout)
                            .accessibilityIdentifier("detail_labour_total")
                        LabourDayList(sections: Array(list.sections.prefix(3)), onEdit: { formRequest = .edit($0) })
                        if list.sections.count > 3 {
                            NavigationLink { makeAll() } label: { Text("detail.labour.all").font(DSTypography.callout) }
                                .frame(minHeight: DSSpacing.minTouch)
                                .accessibilityIdentifier("detail_labour_all")
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail_labour")
        .task { await viewModel.start() }
        .sheet(item: $formRequest) { request in makeForm(request) }
    }
}
