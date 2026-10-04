import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// "Log labour" for several people at once, or edit one entry (spec §5.5).
public struct LabourFormView: View {
    @Bindable private var viewModel: LabourFormViewModel
    private let onClose: () -> Void
    @State private var addingPerson = false
    @State private var confirmDelete = false
    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale

    public init(viewModel: LabourFormViewModel, onClose: @escaping () -> Void) { self.viewModel = viewModel; self.onClose = onClose }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    Card {
                        DatePicker("labour.date", selection: Binding(get: { viewModel.draft.workDate.noonDate(in: timeZone) },
                                                                    set: { viewModel.draft.workDate = CalendarDate($0, timeZone: timeZone) }),
                                   displayedComponents: .date)
                            .accessibilityIdentifier("labour_date")
                    }
                    daysCard
                    crewCard
                    Card {
                        TextField("labour.notes", text: $viewModel.draft.notes, axis: .vertical)
                            .lineLimit(2...4)
                            .accessibilityIdentifier("labour_notes")
                    }
                    HStack {
                        Text("labour.total").font(DSTypography.headline)
                        Spacer()
                        Text(verbatim: moneyText(viewModel.total)).font(DSTypography.money(.title3))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("labour_total")
                    if viewModel.isEditing {
                        Button("labour.delete", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity, minHeight: DSSpacing.minTouch)
                            .accessibilityIdentifier("labour_delete")
                    }
                }
                .padding(DSSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DSColor.background)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(saveKey, systemImage: "checkmark") { Task { if await viewModel.save() { onClose() } } }
                    .disabled(!viewModel.canSubmit)
                    .accessibilityIdentifier("labour_save")
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.vertical, DSSpacing.sm)
                    .keyboardToolbarClearance()
                    .background(DSColor.background)
            }
            .navigationTitle(titleKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("sheet.cancel", action: onClose).accessibilityIdentifier("labour_cancel")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("keyboard.done") { KeyboardDismiss.dismiss() }.accessibilityIdentifier("labour_keyboard_done")
                }
            }
            .task { await viewModel.start() }
            .task { await viewModel.startEntries() }
            .sheet(isPresented: $addingPerson) {
                CrewFormSheet(employee: nil, currency: viewModel.currency,
                              onSave: { draft in
                                  let error = await viewModel.addPerson(draft)
                                  if error == nil { addingPerson = false }
                                  return error
                              },
                              onDelete: nil, onCancel: { addingPerson = false })
            }
            .confirmationDialog("labour.delete.title", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("labour.delete.confirm", role: .destructive) { Task { if await viewModel.delete() { onClose() } } }
                    .accessibilityIdentifier("labour_delete_confirm")
                Button("sheet.cancel", role: .cancel) {}
            } message: {
                Text("labour.delete.message")
            }
            .alert(viewModel.alertKey ?? "labour.error.saveFailed",
                   isPresented: Binding(get: { viewModel.alertKey != nil }, set: { if !$0 { viewModel.alertKey = nil } })) {
                Button("sheet.ok") { if viewModel.loadFailed { onClose() } }
            }
        }
    }

    // MARK: Sections

    private var daysCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                HStack(spacing: DSSpacing.sm) {
                    Text("labour.days").font(DSTypography.headline)
                    Spacer()
                    Button { viewModel.draft.stepDays(up: false) } label: { Image(systemName: "minus.circle").font(DSTypography.title) }
                        .frame(minWidth: DSSpacing.minTouch, minHeight: DSSpacing.minTouch)
                        .accessibilityLabel(Text("labour.days.minus"))
                        .accessibilityIdentifier("labour_days_minus")
                    DecimalField("labour.days", value: $viewModel.draft.days)
                        .frame(width: 72)
                        .accessibilityIdentifier("labour_days")
                    Button { viewModel.draft.stepDays(up: true) } label: { Image(systemName: "plus.circle").font(DSTypography.title) }
                        .frame(minWidth: DSSpacing.minTouch, minHeight: DSSpacing.minTouch)
                        .accessibilityLabel(Text("labour.days.plus"))
                        .accessibilityIdentifier("labour_days_plus")
                }
                if !viewModel.isEditing {
                    Text("labour.days.hint").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                }
                errorText(.daysMissing)
                errorText(.daysNotPositive)
            }
        }
    }

    private var crewCard: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Text("labour.crew").font(DSTypography.headline)
                    Spacer()
                    if !viewModel.isEditing && !viewModel.rows.isEmpty {
                        Button { addingPerson = true } label: { Label("crew.add", systemImage: "person.badge.plus") }
                            .font(DSTypography.callout)
                            .frame(minHeight: DSSpacing.minTouch)
                            .accessibilityIdentifier("labour_add_person")
                    }
                }
                if !viewModel.isEditing && viewModel.isLoaded && viewModel.rows.isEmpty {
                    VStack(spacing: DSSpacing.md) {
                        EmptyState(systemImage: "person.2", title: "crew.empty.title", message: "crew.empty.message")
                        SecondaryButton("crew.add", systemImage: "person.badge.plus") { addingPerson = true }
                            .accessibilityIdentifier("labour_add_person")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("labour_empty_crew")
                }
                ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                    personRow(index, row)
                }
                errorText(.noCrewSelected)
                errorText(.rateMissing)
                errorText(.rateNegative)
            }
        }
    }

    @ViewBuilder
    private func personRow(_ index: Int, _ row: LabourFormViewModel.PersonRow) -> some View {
        let selected = viewModel.draft.isSelected(row.id)
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Button { viewModel.toggle(row.id) } label: {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? DSColor.accent : DSColor.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        (row.name.isEmpty ? Text("labour.unknownPerson") : Text(verbatim: row.name))
                            .font(DSTypography.callout).foregroundStyle(DSColor.textPrimary)
                        if let trade = row.trade { Text(verbatim: trade).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
                    }
                    Spacer()
                    if let rate = row.dailyRate {
                        Text("labour.rate.perDay \(money(rate))").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                    }
                }
                .frame(minHeight: DSSpacing.minTouch)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isEditing)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("labour_person_\(index)")
            if selected {
                HStack(spacing: DSSpacing.sm) {
                    MoneyField("labour.rate", amount: Binding(get: { viewModel.draft.lines.first { $0.employeeId == row.id }?.dailyRate },
                                                              set: { viewModel.draft.setRate($0, for: row.id) }),
                               currencyCode: viewModel.currency.rawValue)
                        .accessibilityIdentifier("labour_rate_\(index)")
                    Text("labour.cost \(moneyText(viewModel.cost(for: row.id)))")
                        .font(DSTypography.money(.callout))
                        .accessibilityIdentifier("labour_cost_\(index)")
                }
                .padding(.leading, DSSpacing.xl)
                if viewModel.showErrors, let error = viewModel.draft.lineError(for: row.id) {
                    Text(error.messageKey).font(DSTypography.caption).foregroundStyle(DSColor.danger)
                        .padding(.leading, DSSpacing.xl)
                        .accessibilityIdentifier("labour_rate_error_\(index)")
                }
                let already = viewModel.alreadyLogged(row.id)
                if already > 0 {
                    Label { Text("labour.already \(LabourDays.text(already, locale: locale))") } icon: { Image(systemName: "exclamationmark.circle") }
                        .font(DSTypography.caption).foregroundStyle(DSColor.warning)
                        .padding(.leading, DSSpacing.xl)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("labour_already_\(index)")
                }
            }
        }
    }

    // MARK: Helpers

    private var titleKey: LocalizedStringKey { viewModel.isEditing ? "labour.edit.title" : "labour.new.title" }
    private var saveKey: LocalizedStringKey { viewModel.isEditing ? "sheet.save" : "labour.save" }

    @ViewBuilder
    private func errorText(_ error: LabourDraftError) -> some View {
        if viewModel.showErrors && viewModel.errors.contains(error) {
            Text(error.messageKey).font(DSTypography.caption).foregroundStyle(DSColor.danger).accessibilityIdentifier("labour_error_" + error.name)
        }
    }

    private func money(_ m: Money) -> String { MoneyFormat.string(m.amount, currencyCode: m.currency.rawValue, locale: locale) }
    private func moneyText(_ m: Money?) -> String { m.map(money) ?? "—" } // lint:allow-string
}
