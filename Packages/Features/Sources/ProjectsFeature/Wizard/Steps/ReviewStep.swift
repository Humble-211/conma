import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct ReviewStep: View {
    @Bindable var viewModel: ProjectWizardViewModel

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            Card {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text("wizard.review.projectName").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                    TextField("wizard.review.projectName", text: Binding(get: { viewModel.draft.projectName ?? "" },
                                                                        set: { viewModel.draft.projectName = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }),
                              prompt: Text(verbatim: ProjectDraftAssembler.defaultName(for: viewModel.draft) ?? ""))
                        .font(DSTypography.title).accessibilityIdentifier("wizard_review_name")
                }
            }
            section(.jobType, missing: [.jobType, .customJobType]) {
                if let type = viewModel.draft.jobType {
                    if type == .other { Text(verbatim: viewModel.draft.customJobType ?? "") } else { Text(type.titleKey) }
                }
            }
            section(.customer, missing: [.customer]) {
                switch viewModel.draft.customer {
                case .existing?: Text("wizard.review.existingCustomer")
                case .new(let input)?: Text(verbatim: input.name)
                case nil: EmptyView()
                }
            }
            section(.location, missing: [.addressLine]) {
                if let a = viewModel.draft.address { Text(verbatim: [a.line, a.unit, a.city, a.region, a.postalCode].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")) }
            }
            section(.scope) {
                if let d = viewModel.draft.scopeDescription { Text(verbatim: d) }
                let count = viewModel.draft.scopeFields.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }.count
                Text(verbatim: "\(count)").font(DSTypography.caption) + Text(verbatim: " ").font(DSTypography.caption) + Text("wizard.review.fields").font(DSTypography.caption)
            }
            section(.timeline) {
                if let s = viewModel.draft.startDate, let e = viewModel.draft.estimatedCompletionDate { Text(verbatim: "\(s.storageString) → \(e.storageString)") }
            }
            section(.labour) { moneyLine(viewModel.preview.estimateByGroup[.labour]) }
            section(.material) { moneyLine(viewModel.preview.estimateByGroup[.material]) }
            section(.otherCosts) { moneyLine(otherTotal) }
            section(.price, missing: [.contractValue]) {
                if let c = viewModel.draft.contractValue { MoneyText(amount: c.amount, currencyCode: viewModel.currency.rawValue, style: .headline) }
                if let profit = viewModel.preview.projectedProfit {
                    HStack { Text("wizard.price.profit").font(DSTypography.caption); Spacer(); MoneyText(amount: profit.amount, currencyCode: viewModel.currency.rawValue, style: .caption) }
                }
            }
            section(.deposit) { moneyLine(viewModel.preview.depositAmount) }
            section(.schedule) {
                ForEach(viewModel.draft.schedule) { row in
                    HStack { RowLabel.text(row.label).font(DSTypography.callout); Spacer(); if let a = row.amount { MoneyText(amount: a.amount, currencyCode: viewModel.currency.rawValue, style: .callout) } }
                }
            }
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    private var otherTotal: Money? {
        let groups: [CostGroup] = [.subcontractor, .equipment, .permit, .other]
        let values = groups.compactMap { viewModel.preview.estimateByGroup[$0] }
        return values.isEmpty ? nil : try? Money.sum(values, currency: viewModel.currency)
    }

    @ViewBuilder private func moneyLine(_ money: Money?) -> some View {
        if let money { MoneyText(amount: money.amount, currencyCode: viewModel.currency.rawValue) } else { Text("wizard.review.notSet").foregroundStyle(DSColor.textSecondary) }
    }

    private func section<Content: View>(_ step: WizardStep, missing: Set<DraftField> = [], @ViewBuilder content: () -> Content) -> some View {
        let isMissing = !viewModel.missing.isDisjoint(with: missing)
        return Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Text(step.titleKey).font(DSTypography.headline).foregroundStyle(isMissing ? DSColor.danger : DSColor.textPrimary)
                    Spacer()
                    Button(isMissing ? "wizard.review.fix" : "wizard.review.edit") { viewModel.go(to: step) }
                        .font(DSTypography.callout).accessibilityIdentifier("wizard_review_fix_" + String(describing: step))
                }
                content()
            }
        }
        .overlay(RoundedRectangle(cornerRadius: DSSpacing.cardRadius, style: .continuous).strokeBorder(isMissing ? DSColor.danger : .clear, lineWidth: 1))
    }
}
