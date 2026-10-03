import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct MaterialStep: View {
    @Bindable var viewModel: ProjectWizardViewModel
    var body: some View {
        EstimateLineList(lines: $viewModel.draft.materialLines, group: .material, currency: viewModel.currency, showsRate: false,
                         suggestions: MaterialSuggestions.labels(for: viewModel.draft.jobType), kindPicker: false)
    }
}
