import SwiftUI
import Domain
import FeatureSupport

/// "Capture first, fill later": a new expense opens the scanner first (Cancel = skip), then the form.
public struct ExpenseFlowView: View {
    private let viewModel: ExpenseFormViewModel
    private let captureMode: ReceiptCaptureMode
    private let onClose: () -> Void
    @State private var scanning: Bool

    public init(viewModel: ExpenseFormViewModel, captureMode: ReceiptCaptureMode, onClose: @escaping () -> Void) {
        self.viewModel = viewModel; self.captureMode = captureMode; self.onClose = onClose
        _scanning = State(initialValue: !viewModel.isEditing && captureMode.isScannerAvailable)
    }

    public var body: some View {
        if scanning {
            ReceiptScannerView(mode: captureMode, onFinish: { pages in viewModel.addPages(pages); scanning = false }, onCancel: { scanning = false })
        } else {
            NavigationStack { ExpenseFormView(viewModel: viewModel, captureMode: captureMode, onClose: onClose) }
        }
    }
}
