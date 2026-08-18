import AppKit
import CoreImage
import Foundation

enum SemanticMaskCompositor {
    enum CompositingError: LocalizedError {
        case unreadableImage
        case renderFailed
        case encodeFailed

        var errorDescription: String? {
            switch self {
            case .unreadableImage: "局部改图结果、原图或蒙版无法读取。"
            case .renderFailed: "无法将局部改图结果合成回原图。"
            case .encodeFailed: "无法保存局部改图合成结果。"
            }
        }
    }

    static func composite(
        generatedData: Data,
        sourceData: Data,
        maskData: Data
    ) throws -> Data {
        guard let source = CIImage(data: sourceData, options: [.applyOrientationProperty: true]),
              let generated = CIImage(data: generatedData, options: [.applyOrientationProperty: true]),
              let mask = CIImage(data: maskData, options: [.applyOrientationProperty: true]),
              source.extent.width > 0,
              source.extent.height > 0 else {
            throw CompositingError.unreadableImage
        }

        let targetExtent = CGRect(origin: .zero, size: source.extent.size)
        guard let filter = CIFilter(name: "CIBlendWithMask") else {
            throw CompositingError.renderFailed
        }
        filter.setValue(fitted(generated, to: targetExtent), forKey: kCIInputImageKey)
        filter.setValue(source.cropped(to: targetExtent), forKey: kCIInputBackgroundImageKey)
        filter.setValue(fitted(mask, to: targetExtent), forKey: kCIInputMaskImageKey)
        guard let output = filter.outputImage?.cropped(to: targetExtent) else {
            throw CompositingError.renderFailed
        }

        let context = CIContext(options: [.cacheIntermediates: false])
        guard let cgImage = context.createCGImage(output, from: targetExtent) else {
            throw CompositingError.renderFailed
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CompositingError.encodeFailed
        }
        return png
    }

    private static func fitted(_ image: CIImage, to extent: CGRect) -> CIImage {
        let translated = image.transformed(
            by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY)
        )
        return translated
            .transformed(
                by: CGAffineTransform(
                    scaleX: extent.width / max(1, translated.extent.width),
                    y: extent.height / max(1, translated.extent.height)
                )
            )
            .cropped(to: extent)
    }
}
