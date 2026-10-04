import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// "See all": every day of the project's labour.
public struct ProjectLabourListView: View {
    private let viewModel: ProjectLabourViewModel
    private let makeForm: (LabourFormRequest) -> AnyView
    @State private var formRequest: LabourFormRequest?
    @State private var retryToken = 0

    public init(viewModel: ProjectLabourViewModel, makeForm: @escaping (LabourFormRequest) -> AnyView) { self.viewModel = viewModel; self.makeForm = makeForm }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                if let errorKey = viewModel.errorKey {
                    LabourLoadError(messageKey: errorKey) { viewModel.retry(); retryToken += 1 }
                } else {
                    LabourDayList(sections: viewModel.list?.sections ?? [], onEdit: { formRequest = .edit($0) })
                }
            }
            .padding(DSSpacing.lg)
        }
        .background(DSColor.background)
        .navigationTitle("labour.list.title")
        .accessibilityIdentifier("labour_list")
        .task(id: retryToken) { await viewModel.start() }
        .sheet(item: $formRequest) { request in makeForm(request) }
    }
}
