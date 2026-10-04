import SwiftUI

/// Pinch to zoom 1×…5×, drag while zoomed, double-tap back to 1×. At 1× drags pass through (page swipes keep working).
public struct ZoomableImage: View {
    private let image: Image
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(image: Image) { self.image = image }

    public var body: some View {
        image.resizable().scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(MagnifyGesture()
                .onChanged { value in scale = min(5, max(1, lastScale * value.magnification)) }
                .onEnded { _ in lastScale = scale; if scale == 1 { offset = .zero; lastOffset = .zero } })
            .gesture(DragGesture()
                .onChanged { value in offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height) }
                .onEnded { _ in lastOffset = offset },
                     including: scale > 1 ? .all : .subviews)
            .onTapGesture(count: 2) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero }
            }
    }
}
