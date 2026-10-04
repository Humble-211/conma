import SwiftUI

/// A receipt page tile (64×88) with its page number; placeholder when the image cannot be loaded.
public struct ReceiptThumbnail: View {
    private let image: Image?
    private let pageNumber: Int

    public init(image: Image?, pageNumber: Int) { self.image = image; self.pageNumber = pageNumber }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image { image.resizable().scaledToFill() }
                else { DSColor.surface.overlay(Image(systemName: "doc.text").foregroundStyle(DSColor.textSecondary)) }
            }
            .frame(width: 64, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: DSSpacing.sm))
            .overlay(RoundedRectangle(cornerRadius: DSSpacing.sm).strokeBorder(DSColor.border, lineWidth: 1))
            Text(verbatim: "\(pageNumber)")
                .font(DSTypography.caption)
                .padding(.horizontal, DSSpacing.xs)
                .background(.thinMaterial, in: Capsule())
                .padding(DSSpacing.xs)
        }
        .frame(minWidth: DSSpacing.minTouch, minHeight: DSSpacing.minTouch)
    }
}
