import SwiftUI
import PhotosUI
import Domain
import DesignSystem
import FeatureSupport

/// One form for new and existing expenses (spec §5.2). Required: project, amount > 0, category.
public struct ExpenseFormView: View {
    @Bindable var viewModel: ExpenseFormViewModel
    let captureMode: ReceiptCaptureMode
    let onClose: () -> Void
    @State private var showScanner = false
    @State private var showPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showCategoryPicker = false
    @State private var showProjectPicker = false
    @State private var showMore = false
    @State private var viewer: ViewerStart?
    @State private var confirmDelete = false
    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale

    struct ViewerStart: Identifiable { let index: Int; var id: Int { index } }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                receipts
                Card {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        MoneyField("expense.amount", amount: $viewModel.draft.amount, currencyCode: viewModel.currency.rawValue, autoFocus: !viewModel.isEditing)
                            .accessibilityIdentifier("expense_amount")
                        errorText(.amountMissing)
                        errorText(.amountNotPositive)
                    }
                }
                categories
                projectRow
                tax
                Card {
                    DatePicker("expense.date", selection: Binding(get: { viewModel.draft.spentOn.noonDate(in: timeZone) },
                                                                 set: { viewModel.draft.spentOn = CalendarDate($0, timeZone: timeZone) }),
                               displayedComponents: .date)
                        .accessibilityIdentifier("expense_date")
                }
                HStack {
                    Text("expense.total").font(DSTypography.headline)
                    Spacer()
                    Text(verbatim: moneyText(viewModel.total)).font(DSTypography.money(.title3))
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("expense_total")
                moreDetails
                if viewModel.isEditing {
                    Button("expense.delete", role: .destructive) { confirmDelete = true }
                        .frame(maxWidth: .infinity, minHeight: DSSpacing.minTouch)
                        .accessibilityIdentifier("expense_delete")
                }
            }
            .padding(DSSpacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DSColor.background)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton("expense.save", systemImage: "checkmark") { Task { if await viewModel.save() { onClose() } } }
                .disabled(viewModel.isSaving)
                .accessibilityIdentifier("expense_save")
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.sm)
                .background(DSColor.background)
        }
        .navigationTitle(titleKey)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("sheet.cancel", action: onClose).accessibilityIdentifier("expense_cancel")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("expense.keyboard.done") { KeyboardDismiss.dismiss() }.accessibilityIdentifier("expense_keyboard_done")
            }
        }
        .task { await viewModel.start() }
        .onChange(of: viewModel.original?.id) { _, _ in
            if let expense = viewModel.original,
               !(expense.vendorName ?? "").isEmpty || !(expense.notes ?? "").isEmpty || expense.paymentMethod != nil {
                showMore = true
            }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: max(1, viewModel.remainingPages), matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var raw: [Data] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) { raw.append(data) }
                }
                let jpegs = await ReceiptImageProcessor.jpegs(fromImageData: raw)
                viewModel.addPages(jpegs)
                photoItems = []
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            ReceiptScannerView(mode: captureMode, onFinish: { viewModel.addPages($0); showScanner = false }, onCancel: { showScanner = false })
        }
        .fullScreenCover(item: $viewer) { start in
            ReceiptViewer(pages: viewModel.pages.map { ReceiptViewerPage(id: $0.id, image: image(for: $0)) },
                          startIndex: start.index,
                          shareURLs: viewModel.pages.compactMap { page -> URL? in
                              if case .saved(let image) = page { return viewModel.fileURL(image) } else { return nil }
                          },
                          onClose: { viewer = nil })
        }
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerSheet(viewModel: viewModel) { showCategoryPicker = false }
        }
        .sheet(isPresented: $showProjectPicker) {
            ProjectPickerSheet(projects: viewModel.projects, selected: viewModel.draft.projectId) { id in
                viewModel.draft.projectId = id
                showProjectPicker = false
            }
        }
        .confirmationDialog("expense.delete.title", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("expense.delete.confirm", role: .destructive) { Task { if await viewModel.delete() { onClose() } } }
                .accessibilityIdentifier("expense_delete_confirm")
            Button("sheet.cancel", role: .cancel) {}
        } message: {
            Text("expense.delete.message")
        }
        .alert(viewModel.alertKey ?? "expense.error.saveFailed",
               isPresented: Binding(get: { viewModel.alertKey != nil }, set: { if !$0 { viewModel.alertKey = nil } })) {
            Button("sheet.ok") {}
        }
        .alert("expense.receipt.limit", isPresented: $viewModel.limitNotice) { Button("sheet.ok") {} }
    }

    // MARK: Sections

    private var receipts: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Text("expense.receipt.title").font(DSTypography.headline)
                    Spacer()
                    Text("expense.receipt.count \(viewModel.pages.count)")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .accessibilityIdentifier("expense_receipt_count")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.sm) {
                        ForEach(Array(viewModel.pages.enumerated()), id: \.element.id) { index, page in
                            ZStack(alignment: .topTrailing) {
                                Button { viewer = ViewerStart(index: index) } label: {
                                    ReceiptThumbnail(image: image(for: page), pageNumber: index + 1)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("expense_receipt_thumb_\(index)")
                                Button { viewModel.removePage(page.id) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(DSColor.onAccent, DSColor.textSecondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("expense.receipt.remove"))
                                .accessibilityIdentifier("expense_receipt_remove_\(index)")
                            }
                        }
                        if viewModel.remainingPages > 0 {
                            Menu {
                                if captureMode.isScannerAvailable {
                                    Button { showScanner = true } label: { Label("expense.receipt.scan", systemImage: "doc.viewfinder") }
                                        .accessibilityIdentifier("expense_receipt_scan")
                                }
                                Button { showPhotos = true } label: { Label("expense.receipt.photos", systemImage: "photo.on.rectangle") }
                                    .accessibilityIdentifier("expense_receipt_photos")
                            } label: {
                                Label("expense.receipt.add", systemImage: "plus")
                                    .labelStyle(.iconOnly)
                                    .font(DSTypography.headline)
                                    .foregroundStyle(DSColor.accent)
                                    .frame(width: 64, height: 88)
                                    .background(DSColor.background, in: RoundedRectangle(cornerRadius: DSSpacing.sm))
                                    .overlay(RoundedRectangle(cornerRadius: DSSpacing.sm).strokeBorder(DSColor.border, lineWidth: 1))
                            }
                            .accessibilityLabel(Text("expense.receipt.add"))
                            .accessibilityIdentifier("expense_receipt_add")
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("expense_receipts")
    }

    private var categories: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                Text("expense.category").font(DSTypography.headline)
                ChoiceChips(options: viewModel.quickCategories, selection: $viewModel.draft.category,
                            text: { $0.title(customName: viewModel.name(for: $0)) },
                            identifier: { chipIdentifier($0) })
                    .padding(.horizontal, -DSSpacing.lg)
                Button("expense.category.more") { showCategoryPicker = true }
                    .frame(minHeight: DSSpacing.minTouch)
                    .accessibilityIdentifier("expense_category_more")
                errorText(.categoryMissing)
            }
        }
    }

    private var projectRow: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Button { showProjectPicker = true } label: {
                HStack {
                    Text("expense.project").foregroundStyle(DSColor.textPrimary)
                    Spacer()
                    if let name = viewModel.selectedProjectName {
                        Text(verbatim: name).foregroundStyle(DSColor.textPrimary).lineLimit(1)
                    } else {
                        Text("expense.project.choose").foregroundStyle(DSColor.textSecondary)
                    }
                    Image(systemName: "chevron.right").foregroundStyle(DSColor.textSecondary)
                }
                .padding(DSSpacing.lg)
                .frame(minHeight: DSSpacing.minTouch)
                .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DSSpacing.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DSSpacing.cardRadius, style: .continuous).strokeBorder(DSColor.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("expense_project")
            errorText(.projectMissing)
        }
    }

    private var tax: some View {
        Card {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                HStack {
                    Text("expense.tax").font(DSTypography.headline)
                    Spacer()
                    Button(taxToggleKey) { viewModel.toggleTaxMode() }
                        .frame(minHeight: DSSpacing.minTouch)
                        .accessibilityIdentifier("expense_tax_percent_toggle")
                }
                if viewModel.taxMode == .percent {
                    FormRow("expense.tax.percent") {
                        DecimalField("expense.tax.percent", value: $viewModel.taxValue).accessibilityIdentifier("expense_tax_percent")
                    }
                    Text("expense.tax.computed \(moneyText(viewModel.taxAmount))")
                        .font(DSTypography.callout)
                        .foregroundStyle(DSColor.textSecondary)
                        .accessibilityIdentifier("expense_tax_amount")
                } else {
                    MoneyField("expense.tax", amount: $viewModel.taxValue, currencyCode: viewModel.currency.rawValue)
                        .accessibilityIdentifier("expense_tax")
                }
                errorText(.taxNegative)
                errorText(.taxPercentOutOfRange)
            }
        }
    }

    private var moreDetails: some View {
        DisclosureGroup(isExpanded: $showMore) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                TextField("expense.vendor", text: $viewModel.draft.vendorName)
                    .frame(minHeight: DSSpacing.minTouch)
                    .accessibilityIdentifier("expense_vendor")
                Text("expense.paymentMethod").font(DSTypography.caption).foregroundStyle(DSColor.textSecondary)
                ChoiceChips(options: PaymentMethod.allCases, selection: $viewModel.draft.paymentMethod,
                            text: { Text($0.titleKey) }, identifier: { "expense_method_" + $0.rawValue })
                    .padding(.horizontal, -DSSpacing.lg)
                TextField("expense.notes", text: $viewModel.draft.notes, axis: .vertical)
                    .lineLimit(2...5)
                    .accessibilityIdentifier("expense_notes")
            }
            .padding(.top, DSSpacing.sm)
        } label: {
            Text("expense.moreDetails").font(DSTypography.headline)
        }
        .accessibilityIdentifier("expense_more_details")
        .padding(DSSpacing.lg)
        .background(DSColor.surface, in: RoundedRectangle(cornerRadius: DSSpacing.cardRadius, style: .continuous))
    }

    // MARK: Helpers

    private var titleKey: LocalizedStringKey { viewModel.isEditing ? "expense.edit.title" : "expense.new.title" }
    private var taxToggleKey: LocalizedStringKey { viewModel.taxMode == .percent ? "expense.tax.useAmount" : "expense.tax.usePercent" }

    @ViewBuilder
    private func errorText(_ error: ExpenseDraftError) -> some View {
        if viewModel.showErrors && viewModel.errors.contains(error) {
            Text(error.messageKey)
                .font(DSTypography.caption)
                .foregroundStyle(DSColor.danger)
                .accessibilityIdentifier("expense_error_" + error.name)
        }
    }

    private func chipIdentifier(_ choice: ExpenseCategoryChoice) -> String {
        switch choice {
        case .standard(let category): return "expense_category_" + category.rawValue // lint:allow-string
        case .custom(let id):
            let index = viewModel.liveCustomCategories.firstIndex { $0.id == id } ?? 0
            return "expense_category_custom_\(index)" // lint:allow-string
        }
    }

    private func moneyText(_ money: Money?) -> String {
        money.map { MoneyFormat.string($0.amount, currencyCode: $0.currency.rawValue, locale: locale) } ?? "—" // lint:allow-string
    }

    private func image(for page: ReceiptPage) -> Image? {
        let uiImage: UIImage?
        switch page {
        case .saved(let image): uiImage = UIImage(contentsOfFile: viewModel.fileURL(image).path)
        case .new(_, let jpeg): uiImage = UIImage(data: jpeg)
        }
        return uiImage.map { Image(uiImage: $0) }
    }
}
