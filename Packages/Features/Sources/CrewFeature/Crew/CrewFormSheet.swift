import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

/// New (employee == nil) or existing crew member. Only the name is required; the daily rate pre-fills labour.
public struct CrewFormSheet: View {
    private let employee: Employee?
    private let currency: CurrencyCode
    private let onSave: (EmployeeDraft) async -> LocalizedStringKey?
    private let onDelete: (() async -> LocalizedStringKey?)?
    private let onCancel: () -> Void
    @State private var draft: EmployeeDraft
    @State private var showErrors = false
    @State private var errorKey: LocalizedStringKey?
    @State private var saving = false
    @State private var confirmDelete = false
    @Environment(\.locale) private var locale

    public init(employee: Employee?, currency: CurrencyCode, onSave: @escaping (EmployeeDraft) async -> LocalizedStringKey?,
                onDelete: (() async -> LocalizedStringKey?)?, onCancel: @escaping () -> Void) {
        self.employee = employee; self.currency = currency; self.onSave = onSave; self.onDelete = onDelete; self.onCancel = onCancel
        _draft = State(initialValue: employee.map(EmployeeDraft.init(editing:)) ?? EmployeeDraft())
    }

    private var titleKey: LocalizedStringKey { employee == nil ? "crew.new.title" : "crew.edit.title" }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("crew.name", text: $draft.name).textContentType(.name).accessibilityIdentifier("crew_name")
                    errorText(.nameMissing)
                    TextField("crew.trade", text: $draft.trade).accessibilityIdentifier("crew_trade")
                    TextField("crew.phone", text: $draft.phone).keyboardType(.phonePad).textContentType(.telephoneNumber).accessibilityIdentifier("crew_phone")
                }
                Section {
                    FormRow("crew.dailyRate") {
                        MoneyField("crew.dailyRate", amount: $draft.dailyRate, currencyCode: currency.rawValue).accessibilityIdentifier("crew_daily_rate")
                    }
                    Text("crew.dailyRate.hint").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                    FormRow("crew.hourlyRate") {
                        MoneyField("crew.hourlyRate", amount: $draft.hourlyRate, currencyCode: currency.rawValue).accessibilityIdentifier("crew_hourly_rate")
                    }
                    if let daily = draft.dailyFromHourly {
                        Button("crew.dailyFromHourly \(money(daily))") { draft.dailyRate = daily }
                            .accessibilityIdentifier("crew_daily_from_hourly")
                    }
                    errorText(.rateNegative)
                }
                Section {
                    TextField("crew.notes", text: $draft.notes, axis: .vertical).lineLimit(2...5).accessibilityIdentifier("crew_notes")
                }
                if let errorKey {
                    Text(errorKey).foregroundStyle(DSColor.danger).accessibilityIdentifier("crew_error")
                }
                if employee != nil, onDelete != nil {
                    Button("crew.delete", role: .destructive) { confirmDelete = true }.accessibilityIdentifier("crew_delete")
                }
            }
            .navigationTitle(titleKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("sheet.cancel", action: onCancel).accessibilityIdentifier("sheet_cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("sheet.save") { Task { await save() } }.disabled(saving).accessibilityIdentifier("crew_save")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("keyboard.done") { KeyboardDismiss.dismiss() }
                }
            }
            .confirmationDialog("crew.delete.title", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("crew.delete.confirm", role: .destructive) { Task { if let onDelete { errorKey = await onDelete() } } }
                    .accessibilityIdentifier("crew_delete_confirm")
                Button("sheet.cancel", role: .cancel) {}
            } message: {
                Text("crew.delete.message")
            }
        }
    }

    private func save() async {
        showErrors = true
        guard draft.canSave, !saving else { return }
        saving = true
        errorKey = await onSave(draft)
        saving = false
    }

    @ViewBuilder
    private func errorText(_ error: EmployeeDraftError) -> some View {
        if showErrors && draft.errors.contains(error) {
            Text(error.messageKey).font(DSTypography.caption).foregroundStyle(DSColor.danger).accessibilityIdentifier("crew_error_" + error.name)
        }
    }

    private func money(_ value: Decimal) -> String { MoneyFormat.string(value, currencyCode: currency.rawValue, locale: locale) }
}
