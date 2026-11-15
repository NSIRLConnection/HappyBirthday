import UIKit

extension UIImage {
    /// Returns a redrawn copy suitable for persistence: downscaled so its
    /// longest edge is at most `maxDimension`, with orientation metadata baked
    /// into the pixels. Keeping a sensible size avoids storing a multi-megapixel
    /// capture when a details thumbnail is all that is needed.
    func normalizedForStorage(maxDimension: CGFloat = 1024) -> UIImage {
        let longestSide = max(size.width, size.height)
        let scale = (longestSide > maxDimension && longestSide > 0)
            ? maxDimension / longestSide
            : 1
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
