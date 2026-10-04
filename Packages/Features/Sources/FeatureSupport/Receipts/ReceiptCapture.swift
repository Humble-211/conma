import SwiftUI
import VisionKit
import DesignSystem

public enum ReceiptCaptureMode: Sendable {
    case live, fake

    /// `.live` needs VisionKit document scanning (false on the simulator → the flow skips straight to the form).
    @MainActor public var isScannerAvailable: Bool { self == .fake || VNDocumentCameraViewController.isSupported }
}

/// Returns processed JPEG pages (`ReceiptImageProcessor`); Cancel means "skip the photo".
public struct ReceiptScannerView: View {
    private let mode: ReceiptCaptureMode
    private let onFinish: ([Data]) -> Void
    private let onCancel: () -> Void

    public init(mode: ReceiptCaptureMode, onFinish: @escaping ([Data]) -> Void, onCancel: @escaping () -> Void) {
        self.mode = mode; self.onFinish = onFinish; self.onCancel = onCancel
    }

    public var body: some View {
        switch mode {
        case .live: DocumentCameraView(onFinish: onFinish, onCancel: onCancel).ignoresSafeArea()
        case .fake: FakeReceiptScannerView(onFinish: onFinish, onCancel: onCancel)
        }
    }
}

struct DocumentCameraView: UIViewControllerRepresentable {
    let onFinish: ([Data]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish, onCancel: onCancel) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([Data]) -> Void
        let onCancel: () -> Void
        init(onFinish: @escaping ([Data]) -> Void, onCancel: @escaping () -> Void) { self.onFinish = onFinish; self.onCancel = onCancel }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish((0..<scan.pageCount).compactMap { ReceiptImageProcessor.jpeg(from: scan.imageOfPage(at: $0)) })
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onCancel() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { onCancel() }
    }
}

/// `--fake-scanner` (UI tests only): one sample page or skip.
struct FakeReceiptScannerView: View {
    let onFinish: ([Data]) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: DSSpacing.lg) {
                Image(systemName: "doc.viewfinder").font(.system(size: 64)).foregroundStyle(DSColor.textSecondary)
                PrimaryButton("scanner.fake.capture", systemImage: "camera") { onFinish([SampleReceipt.scannerSample].compactMap { $0 }) }
                    .accessibilityIdentifier("scanner_capture")
                SecondaryButton("scanner.fake.cancel", action: onCancel)
                    .accessibilityIdentifier("scanner_cancel")
            }
            .padding(DSSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DSColor.background)
            .navigationTitle("scanner.fake.title")
            .accessibilityIdentifier("fake_scanner")
        }
    }
}
