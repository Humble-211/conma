import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct OtherCostsStep: View {
    @Bindable var viewModel: ProjectWizardViewModel
    var body: some View {
        EstimateLineList(lines: $viewModel.draft.otherLines, group: .other, currency: viewModel.currency, showsRate: false, suggestions: [], kindPicker: true)
    }
}
