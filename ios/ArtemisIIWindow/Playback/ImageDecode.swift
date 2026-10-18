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
}
