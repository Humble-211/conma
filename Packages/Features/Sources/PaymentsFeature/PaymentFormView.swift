import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// Record or edit one customer payment (spec §5.2). The project is fixed by the entry point; the amount is the only required field.
public struct PaymentFormView: View {
    @Bindable private var viewModel: PaymentFormViewModel
    private let onClose: () -> Void
    @State private var confirmDelete = false
    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale

    public init(viewModel: PaymentFormViewModel, onClose: @escaping () -> Void) { self.viewModel = viewModel; self.onClose = onClose }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    if let name = viewModel.projectName {
                        Label { Text(verbatim: name) } icon: { Image(systemName: "folder") }
                            .font(DSTypography.callout)
                            .foregroundStyle(DSColor.textSecondary)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("payment_project")
                    }
                    amountCard
                    if !viewModel.options.isEmpty { itemsCard }
                    Card {
                        DatePicker("payment.date", selection: Binding(get: { viewModel.draft.paidOn.noonDate(in: timeZone) },
                                                                     set: { viewModel.draft.paidOn = CalendarDate($0, timeZone: timeZone) }),
                                   displayedComponents: .date)
                            .accessibilityIdentifier("payment_date")
                    }
                    Card {
                        VStack(alignment: .leading, spacing: DSSpacing.sm) {
                            Text("payment.method").font(DSTypography.headline)
                            ChoiceChips(options: PaymentDraft.methodOrder,
                                        selection: Binding(get: { viewModel.draft.method }, set: { if let m = $0 { viewModel.selectMethod(m) } }),
                                        text: { Text($0.titleKey) }, identifier: { "payment_method_" + $0.rawValue })
                                .padding(.horizontal, -DSSpacing.lg)
                        }
                    }
                    Card {
                        TextField("payment.notes", text: $viewModel.draft.notes, axis: .vertical)
                            .lineLimit(2...5)
                            .accessibilityIdentifier("payment_notes")
                    }
                    if viewModel.isEditing {
                        Button("payment.delete", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity, minHeight: DSSpacing.minTouch)
                            .accessibilityIdentifier("payment_delete")
                    }
                }
                .padding(DSSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DSColor.background)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton("payment.save", systemImage: "checkmark") { Task { if await viewModel.save() { onClose() } } }
                    .disabled(!viewModel.canSubmit)
                    .accessibilityIdentifier("payment_save")
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.vertical, DSSpacing.sm)
                    .keyboardToolbarClearance()
                    .background(DSColor.background)
            }
            .navigationTitle(titleKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("sheet.cancel", action: onClose).accessibilityIdentifier("payment_cancel")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("keyboard.done") { KeyboardDismiss.dismiss() }.accessibilityIdentifier("payment_keyboard_done")
                }
            }
            .task { await viewModel.start() }
            .confirmationDialog("payment.delete.title", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("payment.delete.confirm", role: .destructive) { Task { if await viewModel.delete() { onClose() } } }
                    .accessibilityIdentifier("payment_delete_confirm")
                Button("sheet.cancel", role: .cancel) {}
            } message: {
                Text("payment.delete.message")
            }
            .alert(viewModel.alertKey ?? "payment.error.saveFailed",
                   isPresented: Binding(get: { viewModel.alertKey != nil }, set: { if !$0 { viewModel.alertKey = nil } })) {
                Button("sheet.ok") { if viewModel.loadFailed { onClose() } }
            }
        }
    }

    // MARK: Sections

    private var amountCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                MoneyField("payment.amount", amount: $viewModel.draft.amount, currencyCode: viewModel.currency.rawValue, autoFocus: viewModel.focusAmount)
                    .accessibilityIdentifier("payment_amount")
                if !viewModel.suggestions.isEmpty {
                    HStack(spacing: DSSpacing.sm) {
                        ForEach(viewModel.suggestions, id: \.self) { suggestion in
                            Button { viewModel.apply(suggestion) } label: { suggestionText(suggestion).font(DSTypography.callout) }
                                .buttonStyle(.bordered)
                                .frame(minHeight: DSSpacing.minTouch)
                                .accessibilityIdentifier(suggestionIdentifier(suggestion))
                        }
                    }
                }
                if let extra = viewModel.overpayment {
                    Label { Text("payment.overpay \(money(extra))") } icon: { Image(systemName: "info.circle") }
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("payment_overpay_notice")
                }
                errorText(.amountMissing)
                errorText(.amountNotPositive)
            }
        }
    }

    private var itemsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text("payment.items").font(DSTypography.headline)
                ForEach(viewModel.options) { option in
                    itemRow(selected: viewModel.draft.scheduleItemId == option.id, identifier: "payment_item_\(option.item.sortOrder)",
                            action: { viewModel.selectItem(option.id) }) {
                        VStack(alignment: .leading, spacing: 2) {
                            RowLabel.text(option.item.label).font(DSTypography.callout).foregroundStyle(DSColor.textPrimary)
                            Text("payment.item.left \(money(option.remaining))").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                        }
                        Spacer()
                        StatusBadge(option.status.titleKey, tone: option.status.tone)
                    }
                }
                itemRow(selected: viewModel.draft.scheduleItemId == nil, identifier: "payment_item_none", action: { viewModel.selectItem(nil) }) {
                    Text("payment.item.none").font(DSTypography.callout).foregroundStyle(DSColor.textPrimary)
                    Spacer()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("payment_items")
    }

    private func itemRow<Content: View>(selected: Bool, identifier: String, action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? DSColor.accent : DSColor.textSecondary)
                content()
            }
            .frame(minHeight: DSSpacing.minTouch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    // MARK: Helpers

    private var titleKey: LocalizedStringKey { viewModel.isEditing ? "payment.edit.title" : "payment.new.title" }

    private func suggestionText(_ suggestion: PaymentSuggestion) -> Text {
        let amount = money(suggestion.money)
        switch suggestion {
        case .remaining: return Text("payment.chip.remaining \(amount)")
        case .fullItem: return Text("payment.chip.full \(amount)")
        case .outstanding: return Text("payment.chip.outstanding \(amount)")
        }
    }

    private func suggestionIdentifier(_ suggestion: PaymentSuggestion) -> String {
        switch suggestion {
        case .remaining: return "payment_chip_remaining" // lint:allow-string
        case .fullItem: return "payment_chip_full" // lint:allow-string
        case .outstanding: return "payment_chip_outstanding" // lint:allow-string
        }
    }

    @ViewBuilder
    private func errorText(_ error: PaymentDraftError) -> some View {
        if viewModel.showErrors && viewModel.errors.contains(error) {
            Text(error.messageKey)
                .font(DSTypography.caption)
                .foregroundStyle(DSColor.danger)
                .accessibilityIdentifier("payment_error_" + error.name)
        }
    }

    private func money(_ money: Money) -> String { MoneyFormat.string(money.amount, currencyCode: money.currency.rawValue, locale: locale) }
}
