import SwiftUI
import Domain
import DesignSystem
import FeatureSupport

struct ScopeStep: View {
    @Bindable var viewModel: ProjectWizardViewModel
    @Environment(\.locale) private var locale
    @State private var newFieldLabel = ""

    private var definitions: [ScopeFieldDefinition] { viewModel.draft.jobType.map(ScopeFieldCatalog.fields(for:)) ?? ScopeFieldCatalog.common }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            Card {
                TextField("wizard.scope.description", text: Binding(get: { viewModel.draft.scopeDescription ?? "" }, set: { viewModel.draft.scopeDescription = $0.isEmpty ? nil : $0 }), axis: .vertical)
                    .lineLimit(3...6)
                    .accessibilityIdentifier("wizard_scope_description")
            }
            Card {
                VStack(spacing: DSSpacing.md) {
                    ForEach(definitions, id: \.key) { def in
                        fieldRow(def)
                        if def.key != definitions.last?.key { Divider() }
                    }
                }
            }
            if !customFields.isEmpty {
                Card {
                    VStack(spacing: DSSpacing.md) {
                        ForEach(customFields) { field in
                            FormRow(verbatimLabel: ScopeFieldCatalog.customLabel(field.key)) {
                                HStack(spacing: DSSpacing.sm) {
                                    TextField("wizard.scope.value", text: binding(for: field.key)).multilineTextAlignment(.trailing)
                                    Button { remove(field.key) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(DSColor.textSecondary) }
                                        .accessibilityLabel(Text("wizard.scope.remove"))
                                }
                            }
                        }
                    }
                }
            }
            Card {
                HStack {
                    TextField("wizard.scope.newField", text: $newFieldLabel).frame(minHeight: DSSpacing.minTouch)
                    Button { addCustom() } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                        .disabled(newFieldLabel.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("wizard_scope_add")
                }
            }
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    private var customFields: [DraftScopeField] { viewModel.draft.scopeFields.filter { ScopeFieldCatalog.isCustom($0.key) } }

    @ViewBuilder private func fieldRow(_ def: ScopeFieldDefinition) -> some View {
        let label = ScopeFieldCatalog.labelKey(forFieldKey: def.key) ?? "wizard.scope.value"
        switch def.kind {
        case .integer:
            FormRow(label) { IntegerField("wizard.scope.value", value: intBinding(def.key)) }.accessibilityIdentifier("wizard_scope_field_" + def.key)
        case .decimal:
            FormRow(label) {
                HStack(spacing: DSSpacing.xs) {
                    DecimalField("wizard.scope.value", value: decimalBinding(def.key))
                    if let unit = def.unitKey { Text(ScopeFieldCatalog.unitLabelKey(unit)).font(DSTypography.caption).foregroundStyle(DSColor.textSecondary) }
                }
            }.accessibilityIdentifier("wizard_scope_field_" + def.key)
        case .text:
            FormRow(label) { TextField("wizard.scope.value", text: binding(for: def.key)).multilineTextAlignment(.trailing) }
        case .toggle:
            Toggle(isOn: Binding(get: { value(def.key) == "true" }, set: { set(def.key, $0 ? "true" : "false") })) { Text(label) } // lint:allow-string
                .frame(minHeight: DSSpacing.minTouch).tint(DSColor.accent)
        case .choice(let options):
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text(label).font(DSTypography.body)
                ChoiceChips(options: options, selection: Binding(get: { value(def.key).isEmpty ? nil : value(def.key) }, set: { set(def.key, $0 ?? "") }), label: ScopeFieldCatalog.optionLabelKey)
                    .padding(.horizontal, -DSSpacing.lg)
            }
        }
    }

    // MARK: value plumbing (canonical storage)

    private func value(_ key: String) -> String { viewModel.draft.scopeFields.first { $0.key == key }?.value ?? "" }

    private func set(_ key: String, _ newValue: String) {
        if let index = viewModel.draft.scopeFields.firstIndex(where: { $0.key == key }) {
            if newValue.isEmpty { viewModel.draft.scopeFields.remove(at: index) } else { viewModel.draft.scopeFields[index].value = newValue }
        } else if !newValue.isEmpty {
            viewModel.draft.scopeFields.append(DraftScopeField(id: UUID(), key: key, value: newValue, sortOrder: viewModel.draft.scopeFields.count))
        }
    }

    private func binding(for key: String) -> Binding<String> { Binding(get: { value(key) }, set: { set(key, $0) }) }

    private func intBinding(_ key: String) -> Binding<Int?> {
        Binding(get: { Int(value(key)) }, set: { set(key, $0.map(String.init) ?? "") })
    }

    private func decimalBinding(_ key: String) -> Binding<Decimal?> {
        Binding(get: { Decimal(string: value(key), locale: Locale(identifier: "en_US_POSIX")) },
                set: { set(key, $0.map { "\($0)" } ?? "") })
    }

    private func addCustom() {
        let label = newFieldLabel.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return }
        set(ScopeFieldCatalog.customPrefix + label, " ")   // placeholder so the row appears; user types the value // lint:allow-string
        newFieldLabel = ""
    }

    private func remove(_ key: String) { viewModel.draft.scopeFields.removeAll { $0.key == key } }
}
