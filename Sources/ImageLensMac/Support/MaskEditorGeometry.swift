import AppKit
import CoreGraphics
import Foundation

enum MaskEditorTool: String, CaseIterable, Identifiable, Sendable {
    case paint
    case erase
    case pan

    var id: Self { self }

    var title: String {
        switch self {
        case .paint: "画笔"
        case .erase: "擦除"
        case .pan: "抓手"
        }
    }

    var systemImage: String {
        switch self {
        case .paint: "paintbrush.pointed"
        case .erase: "eraser"
        case .pan: "hand.draw"
        }
    }
}

struct MaskEditorStroke: Equatable, Sendable {
    enum Mode: Sendable {
        case paint
        case erase
    }

    var mode: Mode
    var diameterInPixels: CGFloat
    var points: [CGPoint]
}

/// Converts between view coordinates and the source image's canonical pixel
/// coordinates. Mask strokes are persisted in pixel space, so fitting, zooming,
/// panning, window resizing, and Retina backing scale never alter their target.
struct MaskEditorGeometry: Equatable, Sendable {
    static let minimumZoom: CGFloat = 0.25
    static let maximumZoom: CGFloat = 12
    static let defaultViewportInset: CGFloat = 24
    static let minimumVisibleImageLength: CGFloat = 48

    var imagePixelSize: CGSize
    var viewportSize: CGSize
    var zoom: CGFloat
    var pan: CGSize
    var viewportInset: CGFloat

    init(
        imagePixelSize: CGSize,
        viewportSize: CGSize,
        zoom: CGFloat = 1,
        pan: CGSize = .zero,
        viewportInset: CGFloat = Self.defaultViewportInset
    ) {
        self.imagePixelSize = imagePixelSize
        self.viewportSize = viewportSize
        self.zoom = Self.clampedZoom(zoom)
        self.pan = pan
        self.viewportInset = max(0, viewportInset)
    }

    var isValid: Bool {
        imagePixelSize.width.isFinite
            && imagePixelSize.height.isFinite
            && viewportSize.width.isFinite
            && viewportSize.height.isFinite
            && imagePixelSize.width > 0
            && imagePixelSize.height > 0
            && viewportSize.width > 0
            && viewportSize.height > 0
    }

    var fitScale: CGFloat {
        guard isValid else { return 1 }
        let availableWidth = max(1, viewportSize.width - viewportInset * 2)
        let availableHeight = max(1, viewportSize.height - viewportInset * 2)
        return min(
            availableWidth / imagePixelSize.width,
            availableHeight / imagePixelSize.height
        )
    }

    var displayScale: CGFloat { fitScale * Self.clampedZoom(zoom) }

    var imageRect: CGRect {
        guard isValid else { return .zero }
        let displayedSize = CGSize(
            width: imagePixelSize.width * displayScale,
            height: imagePixelSize.height * displayScale
        )
        return CGRect(
            x: (viewportSize.width - displayedSize.width) / 2 + pan.width,
            y: (viewportSize.height - displayedSize.height) / 2 + pan.height,
            width: displayedSize.width,
            height: displayedSize.height
        )
    }

    func imagePoint(fromViewPoint point: CGPoint) -> CGPoint? {
        let rect = imageRect
        guard !rect.isEmpty, rect.contains(point), displayScale > 0 else { return nil }
        return CGPoint(
            x: min(
                imagePixelSize.width,
                max(0, (point.x - rect.minX) / displayScale)
            ),
            y: min(
                imagePixelSize.height,
                max(0, (point.y - rect.minY) / displayScale)
            )
        )
    }

    func viewPoint(fromImagePoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: imageRect.minX + point.x * displayScale,
            y: imageRect.minY + point.y * displayScale
        )
    }

    func constrainedPan(_ candidate: CGSize) -> CGSize {
        guard isValid else { return .zero }
        let rectAtOrigin = CGRect(
            x: (viewportSize.width - imagePixelSize.width * displayScale) / 2,
            y: (viewportSize.height - imagePixelSize.height * displayScale) / 2,
            width: imagePixelSize.width * displayScale,
            height: imagePixelSize.height * displayScale
        )
        let visibleX = min(Self.minimumVisibleImageLength, rectAtOrigin.width)
        let visibleY = min(Self.minimumVisibleImageLength, rectAtOrigin.height)
        let minimumX = visibleX - rectAtOrigin.maxX
        let maximumX = viewportSize.width - visibleX - rectAtOrigin.minX
        let minimumY = visibleY - rectAtOrigin.maxY
        let maximumY = viewportSize.height - visibleY - rectAtOrigin.minY
        return CGSize(
            width: min(max(candidate.width, minimumX), maximumX),
            height: min(max(candidate.height, minimumY), maximumY)
        )
    }

    /// Returns a new zoom/pan pair that keeps the same source-image pixel under
    /// the supplied view-space anchor whenever that anchor is over the image.
    func zoomed(to proposedZoom: CGFloat, around anchor: CGPoint) -> (zoom: CGFloat, pan: CGSize) {
        let nextZoom = Self.clampedZoom(proposedZoom)
        guard isValid else { return (nextZoom, .zero) }
        let sourceAnchor = imagePoint(fromViewPoint: anchor) ?? CGPoint(
            x: imagePixelSize.width / 2,
            y: imagePixelSize.height / 2
        )
        var next = self
        next.zoom = nextZoom
        let nextScale = next.displayScale
        let viewportCenter = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        let sourceOffset = CGPoint(
            x: sourceAnchor.x - imagePixelSize.width / 2,
            y: sourceAnchor.y - imagePixelSize.height / 2
        )
        let candidatePan = CGSize(
            width: anchor.x - viewportCenter.x - sourceOffset.x * nextScale,
            height: anchor.y - viewportCenter.y - sourceOffset.y * nextScale
        )
        next.pan = .zero
        return (nextZoom, next.constrainedPan(candidatePan))
    }

    static func clampedZoom(_ zoom: CGFloat) -> CGFloat {
        guard zoom.isFinite else { return 1 }
        return min(max(zoom, minimumZoom), maximumZoom)
    }
}

enum MaskPNGRenderer {
    enum RenderError: LocalizedError {
        case invalidPixelSize
        case contextCreationFailed
        case imageCreationFailed
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .invalidPixelSize: "原图像素尺寸无效，无法创建蒙版。"
            case .contextCreationFailed: "无法创建蒙版绘图环境。"
            case .imageCreationFailed: "无法生成蒙版图像。"
            case .encodingFailed: "无法将蒙版编码为 PNG。"
            }
        }
    }

    /// Produces an 8-bit grayscale PNG at the source image's exact pixel size.
    /// White pixels are the edit region and black pixels are preserved.
    static func data(
        imagePixelSize: CGSize,
        strokes: [MaskEditorStroke]
    ) throws -> Data {
        guard imagePixelSize.width.isFinite,
              imagePixelSize.height.isFinite,
              imagePixelSize.width > 0,
              imagePixelSize.height > 0 else {
            throw RenderError.invalidPixelSize
        }
        let width = Int(imagePixelSize.width.rounded())
        let height = Int(imagePixelSize.height.rounded())
        guard width > 0, height > 0 else { throw RenderError.invalidPixelSize }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw RenderError.contextCreationFailed
        }

        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Stroke points use the same top-left origin as SwiftUI's image view.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setShouldAntialias(true)

        for stroke in strokes where !stroke.points.isEmpty {
            let gray: CGFloat = stroke.mode == .paint ? 1 : 0
            let diameter = max(1, stroke.diameterInPixels)
            context.setStrokeColor(gray: gray, alpha: 1)
            context.setFillColor(gray: gray, alpha: 1)
            context.setLineWidth(diameter)

            if stroke.points.count == 1, let point = stroke.points.first {
                context.fillEllipse(
                    in: CGRect(
                        x: point.x - diameter / 2,
                        y: point.y - diameter / 2,
                        width: diameter,
                        height: diameter
                    )
                )
                continue
            }

            context.beginPath()
            context.move(to: stroke.points[0])
            for point in stroke.points.dropFirst() {
                context.addLine(to: point)
            }
            context.strokePath()
        }

        guard let image = context.makeImage() else { throw RenderError.imageCreationFailed }
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw RenderError.encodingFailed
        }
        return data
    }

}
