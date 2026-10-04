import UIKit

public enum ReceiptImageProcessor {
    public static let maxLongEdge: CGFloat = 2000
    public static let quality: CGFloat = 0.7

    /// Downscales so the long edge is ≤ 2000 px (never upscales), renders at scale 1, encodes JPEG 0.7.
    public static func jpeg(from image: UIImage) -> Data? {
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let longEdge = max(size.width, size.height)
        guard longEdge > 0 else { return nil }
        let factor = min(1, maxLongEdge / longEdge)
        let target = CGSize(width: (size.width * factor).rounded(), height: (size.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: quality)
    }

    /// Encodes several pages off the main actor (non-isolated async runs on the global executor); pages that fail are dropped.
    public static func jpegs(from images: [UIImage]) async -> [Data] {
        images.compactMap { jpeg(from: $0) }
    }

    /// Photos-picker variant: decodes the raw file data, then encodes like `jpeg(from:)`, off the main actor.
    public static func jpegs(fromImageData items: [Data]) async -> [Data] {
        items.compactMap { UIImage(data: $0).flatMap { jpeg(from: $0) } }
    }
}
