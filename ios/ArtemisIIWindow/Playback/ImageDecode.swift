import CoreGraphics
import Foundation
import ImageIO

/// ImageIO thumbnail decode. Safe to call off the main thread.
/// The image is owned by the caller until the main actor turns it into a `UIImage`.
enum ImageDecode {
    struct Owned: @unchecked Sendable {
        let cgImage: CGImage
    }

    static func thumbnail(url: URL, maxPixel: CGFloat) -> Owned? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return Owned(cgImage: cgImage)
    }

    /// Used only when the ImageIO thumbnail fails. Runs off the main thread and returns a `CGImage`.
    static func downscaled(url: URL, maxPixel: CGFloat) -> Owned? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        guard let full = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let pixelWidth = full.width
        let pixelHeight = full.height
        let longest = max(pixelWidth, pixelHeight)
        guard longest > 0 else { return nil }
        let limit = max(1, Int(maxPixel.rounded(.down)))
        if longest <= limit {
            return Owned(cgImage: full)
        }
        let ratio = Double(limit) / Double(longest)
        let width = max(1, Int((Double(pixelWidth) * ratio).rounded()))
        let height = max(1, Int((Double(pixelHeight) * ratio).rounded()))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Owned(cgImage: full)
        }
        context.interpolationQuality = .high
        context.draw(full, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        guard let scaled = context.makeImage() else { return nil }
        return Owned(cgImage: scaled)
    }
}
