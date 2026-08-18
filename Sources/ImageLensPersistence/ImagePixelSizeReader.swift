import Foundation
import ImageIO
import ImageLensCore

/// Reads display-oriented pixel dimensions from image metadata without
/// decoding the full bitmap. This is the single persistence boundary used by
/// imports and legacy-workspace hydration.
public enum ImagePixelSizeReader {
    public static func pixelSize(from data: Data) -> PixelSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        return pixelSize(from: source)
    }

    public static func pixelSize(at url: URL) -> PixelSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return pixelSize(from: source)
    }

    private static func pixelSize(from source: CGImageSource) -> PixelSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(
            source,
            0,
            nil
        ) as? [CFString: Any],
        let rawWidth = integerValue(properties[kCGImagePropertyPixelWidth]),
        let rawHeight = integerValue(properties[kCGImagePropertyPixelHeight]),
        rawWidth > 0,
        rawHeight > 0 else {
            return nil
        }

        let orientation = integerValue(
            properties[kCGImagePropertyOrientation]
        ) ?? 1
        if 5 ... 8 ~= orientation {
            return PixelSize(width: rawHeight, height: rawWidth)
        }
        return PixelSize(width: rawWidth, height: rawHeight)
    }

    private static func integerValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let value = value as? Int {
            return value
        }
        return nil
    }
}
