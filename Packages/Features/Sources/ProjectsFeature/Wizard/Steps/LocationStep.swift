import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct LocationStep: View {
    @Bindable var viewModel: ProjectWizardViewModel

    private var address: Binding<Address> {
        Binding(get: { viewModel.draft.address ?? Address(line: "", unit: nil, city: nil, region: nil, postalCode: nil) },
                set: { viewModel.draft.address = $0 })
    }

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            Card {
                VStack(spacing: DSSpacing.md) {
                    TextField("wizard.location.line", text: address.line).textContentType(.streetAddressLine1).frame(minHeight: DSSpacing.minTouch).accessibilityIdentifier("wizard_address_line")
                    Divider()
                    TextField("wizard.location.unit", text: optional(address.unit)).textContentType(.streetAddressLine2).frame(minHeight: DSSpacing.minTouch)
                    Divider()
                    TextField("wizard.location.city", text: optional(address.city)).textContentType(.addressCity).frame(minHeight: DSSpacing.minTouch)
                    Divider()
                    HStack(spacing: DSSpacing.md) {
                        TextField("wizard.location.region", text: optional(address.region)).textContentType(.addressState).frame(minHeight: DSSpacing.minTouch)
                        TextField("wizard.location.postalCode", text: optional(address.postalCode)).textContentType(.postalCode).textInputAutocapitalization(.characters).frame(minHeight: DSSpacing.minTouch)
                    }
                }
            }
            SecondaryButton("wizard.location.openMaps", systemImage: "map") { openMaps() }
                .disabled(!viewModel.canContinue).opacity(viewModel.canContinue ? 1 : 0.5)
                .accessibilityIdentifier("wizard_open_maps")
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    private func optional(_ binding: Binding<String?>) -> Binding<String> {
        Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    private func openMaps() {
        let a = address.wrappedValue
        let query = [a.line, a.unit, a.city, a.region, a.postalCode].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ") // lint:allow-string
        var components = URLComponents(string: "maps://")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components?.url else { return }
        UIApplication.shared.open(url)
    }
}
