import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

public struct SetupView: View {
    @Bindable private var viewModel: SetupViewModel
    @Bindable private var settings: AppSettings

    public init(viewModel: SetupViewModel, settings: AppSettings) {
        self.viewModel = viewModel; self.settings = settings
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Text("setup.title").font(DSTypography.largeTitle).foregroundStyle(DSColor.textPrimary)
                    Text("setup.subtitle").font(DSTypography.body).foregroundStyle(DSColor.textSecondary)
                }
                Card {
                    VStack(spacing: DSSpacing.md) {
                        TextField("setup.companyName", text: $viewModel.companyName)
                            .textContentType(.organizationName)
                            .frame(minHeight: DSSpacing.minTouch)
                            .accessibilityIdentifier("setup_company_name")
                        Divider()
                        TextField("setup.yourName", text: $viewModel.ownerName)
                            .textContentType(.name)
                            .frame(minHeight: DSSpacing.minTouch)
                            .accessibilityIdentifier("setup_owner_name")
                        Divider()
                        FormRow("setup.currency") {
                            Picker("setup.currency", selection: $viewModel.currency) {
                                ForEach(CurrencyCode.allCases, id: \.self) { Text($0.titleKey).tag($0) }
                            }
                            .labelsHidden()
                        }
                        Divider()
                        FormRow("setup.language") {
                            Picker("setup.language", selection: $settings.language) {
                                ForEach(LanguageChoice.allCases, id: \.self) { Text($0.titleKey).tag($0) }
                            }
                            .labelsHidden()
                        }
                    }
                }
                if let errorKey = viewModel.errorKey {
                    Text(errorKey).font(DSTypography.callout).foregroundStyle(DSColor.danger)
                }
                Spacer(minLength: DSSpacing.xl)
                PrimaryButton("setup.start", systemImage: "arrow.right", isLoading: viewModel.isSaving) {
                    Task { await viewModel.submit() }
                }
                .disabled(!viewModel.canSubmit)
                .opacity(viewModel.canSubmit ? 1 : 0.5)
                .accessibilityIdentifier("setup_start")
            }
            .padding(DSSpacing.lg)
        }
        .background(DSColor.background)
    }
}
