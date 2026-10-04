import SwiftUI
import DesignSystem
import FeatureSupport

public struct ReceiptViewerPage: Identifiable {
    public let id: UUID
    public let source: ReceiptImageSource
    public init(id: UUID, source: ReceiptImageSource) { self.id = id; self.source = source }
}

/// Decodes its full-size page only while on screen (the pager keeps just the visible and adjacent pages alive).
private struct ReceiptViewerPageView: View {
    let page: ReceiptViewerPage
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                ZoomableImage(image: Image(uiImage: image))
            } else if failed {
                ZoomableImage(image: Image(systemName: "doc.text"))
            } else {
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: page.id) {
            let loaded = await ReceiptImageProcessor.fullImage(of: page.source)
            image = loaded
            failed = loaded == nil
        }
        .onDisappear { image = nil; failed = false }
    }
}

/// Full-screen pager with pinch zoom; shares the saved pages (unsaved pages are viewable, not shareable).
public struct ReceiptViewer: View {
    private let pages: [ReceiptViewerPage]
    private let shareURLs: [URL]
    private let onClose: () -> Void
    @State private var index: Int

    public init(pages: [ReceiptViewerPage], startIndex: Int, shareURLs: [URL], onClose: @escaping () -> Void) {
        self.pages = pages; self.shareURLs = shareURLs; self.onClose = onClose
        _index = State(initialValue: min(max(0, startIndex), max(0, pages.count - 1)))
    }

    public var body: some View {
        NavigationStack {
            TabView(selection: $index) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { offset, page in
                    ReceiptViewerPageView(page: page)
                        .tag(offset)
                        .accessibilityIdentifier("receipt_page_\(offset)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("receipt.viewer.close", action: onClose).accessibilityIdentifier("receipt_close")
                }
                ToolbarItem(placement: .principal) {
                    Text("receipt.viewer.page \(index + 1) \(pages.count)")
                        .font(DSTypography.headline)
                        .accessibilityIdentifier("receipt_page_label")
                }
                if !shareURLs.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(items: shareURLs) { Label("receipt.viewer.share", systemImage: "square.and.arrow.up") }
                            .accessibilityIdentifier("receipt_share")
                    }
                }
            }
            .accessibilityIdentifier("receipt_viewer")
        }
    }
}
