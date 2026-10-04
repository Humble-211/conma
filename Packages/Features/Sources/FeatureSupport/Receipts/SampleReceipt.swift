import UIKit

/// Receipt image drawn in code for the debug seed and the UI-test scanner (no binary asset in the repo).
public enum SampleReceipt {
    public static func jpeg(vendor: String, lines: [(String, String)], total: String) -> Data? {
        let size = CGSize(width: 1200, height: 1800)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let title: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 72), .foregroundColor: UIColor.black]
            let body: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 40, weight: .regular), .foregroundColor: UIColor.darkGray]
            (vendor as NSString).draw(at: CGPoint(x: 80, y: 100), withAttributes: title)
            var y: CGFloat = 260
            for (item, price) in lines {
                (item as NSString).draw(at: CGPoint(x: 80, y: y), withAttributes: body)
                (price as NSString).draw(at: CGPoint(x: 900, y: y), withAttributes: body)
                y += 64
            }
            (("TOTAL " + total) as NSString).draw(at: CGPoint(x: 80, y: y + 80), withAttributes: title)
        }
        return ReceiptImageProcessor.jpeg(from: image)
    }

    public static var scannerSample: Data? {
        jpeg(vendor: "HOME DEPOT #7011", lines: [("2X4 SPF 8FT x 40", "212.40"), ("SCREWS 3IN", "27.61")], total: "240.01")
    }
}
