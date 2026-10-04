import UIKit
import ImageIO

/// Where a receipt page's JPEG lives: a stored file, or bytes not saved yet.
public enum ReceiptImageSource: Sendable {
    case file(URL)
    case data(Data)
}

public enum ReceiptImageProcessor {
    public static let maxLongEdge: CGFloat = 2000
    public static let quality: CGFloat = 0.7
    /// 64×88 pt tile at 3× → 264 px on the long edge.
    public static let thumbnailMaxPixelSize = 264

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

    /// Encodes one page on a background task; intermediate bitmaps are released before it returns.
    public static func encode(_ image: UIImage) async -> Data? {
        await Task.detached(priority: .userInitiated) { autoreleasepool { ReceiptImageProcessor.jpeg(from: image) } }.value
    }

    /// Photos-picker variant for one item: decodes the raw file data, then encodes like `jpeg(from:)`, off the main actor.
    public static func encode(imageData: Data) async -> Data? {
        await Task.detached(priority: .userInitiated) { autoreleasepool { UIImage(data: imageData).flatMap { ReceiptImageProcessor.jpeg(from: $0) } } }.value
    }

    /// Encodes several pages one at a time (only one full-size bitmap alive at once); pages that fail are dropped.
    public static func jpegs(from images: [UIImage]) async -> [Data] {
        var result: [Data] = []
        for image in images { if let jpeg = await encode(image) { result.append(jpeg) } }
        return result
    }

    /// Photos-picker variant: decodes and encodes one item at a time, off the main actor.
    public static func jpegs(fromImageData items: [Data]) async -> [Data] {
        var result: [Data] = []
        for item in items { if let jpeg = await encode(imageData: item) { result.append(jpeg) } }
        return result
    }

    /// A downsampled tile image (ImageIO, never decodes the full bitmap), built off the main actor.
    public static func thumbnail(of source: ReceiptImageSource, maxPixelSize: Int = thumbnailMaxPixelSize) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { ReceiptImageProcessor.makeThumbnail(source, maxPixelSize: maxPixelSize) }.value
    }

    /// The full page for the viewer, decoded off the main actor so the pager does not stutter.
    public static func fullImage(of source: ReceiptImageSource) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let image: UIImage?
            switch source {
            case .file(let url): image = UIImage(contentsOfFile: url.path)
            case .data(let data): image = UIImage(data: data)
            }
            return image?.preparingForDisplay() ?? image
        }.value
    }

    static func makeThumbnail(_ source: ReceiptImageSource, maxPixelSize: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        let imageSource: CGImageSource?
        switch source {
        case .file(let url): imageSource = CGImageSourceCreateWithURL(url as CFURL, sourceOptions)
        case .data(let data): imageSource = CGImageSourceCreateWithData(data as CFData, sourceOptions)
        }
        guard let imageSource else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
