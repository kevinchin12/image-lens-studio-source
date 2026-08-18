import Foundation

/// Converts between the infinite canvas coordinate space and one finite view.
///
/// The transform is `view = world * scale + translation`. Translation is stored
/// in view points, so pointer deltas can be applied directly while panning.
public struct ViewportTransform: Codable, Hashable, Sendable {
    public private(set) var scale: Double
    public private(set) var translation: ViewPoint

    public init(scale: Double = 1, translation: ViewPoint = .zero) {
        precondition(scale.isFinite && scale > 0, "Viewport scale must be finite and positive")
        precondition(translation.x.isFinite && translation.y.isFinite, "Viewport translation must be finite")
        self.scale = scale
        self.translation = translation
    }

    public static let identity = ViewportTransform()

    public func viewPoint(for worldPoint: WorldPoint) -> ViewPoint {
        ViewPoint(
            x: worldPoint.x * scale + translation.x,
            y: worldPoint.y * scale + translation.y
        )
    }

    public func worldPoint(for viewPoint: ViewPoint) -> WorldPoint {
        WorldPoint(
            x: (viewPoint.x - translation.x) / scale,
            y: (viewPoint.y - translation.y) / scale
        )
    }

    public func viewSize(for worldSize: WorldSize) -> ViewSize {
        ViewSize(width: worldSize.width * scale, height: worldSize.height * scale)
    }

    public func worldSize(for viewSize: ViewSize) -> WorldSize {
        WorldSize(width: viewSize.width / scale, height: viewSize.height / scale)
    }

    public func viewRect(for worldRect: WorldRect) -> ViewRect {
        let rect = worldRect.standardized
        return ViewRect(
            origin: viewPoint(for: rect.origin),
            size: viewSize(for: rect.size)
        )
    }

    public func worldRect(for viewRect: ViewRect) -> WorldRect {
        WorldRect(
            origin: worldPoint(for: viewRect.origin),
            size: worldSize(for: viewRect.size)
        ).standardized
    }

    /// Returns the world region currently covered by a view whose origin is zero.
    public func visibleWorldRect(viewportSize: ViewSize) -> WorldRect {
        worldRect(for: ViewRect(origin: .zero, size: viewportSize))
    }

    /// Applies a pointer-sized delta in view points.
    public func pannedBy(x: Double, y: Double) -> ViewportTransform {
        ViewportTransform(
            scale: scale,
            translation: ViewPoint(x: translation.x + x, y: translation.y + y)
        )
    }

    /// Changes zoom while preserving the world point under `anchor`.
    public func zoomed(to newScale: Double, around anchor: ViewPoint) -> ViewportTransform {
        precondition(newScale.isFinite && newScale > 0, "Viewport scale must be finite and positive")
        let anchoredWorldPoint = worldPoint(for: anchor)
        return ViewportTransform(
            scale: newScale,
            translation: ViewPoint(
                x: anchor.x - anchoredWorldPoint.x * newScale,
                y: anchor.y - anchoredWorldPoint.y * newScale
            )
        )
    }

    /// Multiplies zoom and clamps it to the supplied supported range.
    public func zoomed(
        by factor: Double,
        around anchor: ViewPoint,
        limitedTo scaleRange: ClosedRange<Double> = 0.05 ... 16
    ) -> ViewportTransform {
        precondition(factor.isFinite && factor > 0, "Zoom factor must be finite and positive")
        precondition(
            scaleRange.lowerBound.isFinite
                && scaleRange.upperBound.isFinite
                && scaleRange.lowerBound > 0,
            "Scale range must be finite and positive"
        )
        let target = Swift.min(Swift.max(scale * factor, scaleRange.lowerBound), scaleRange.upperBound)
        return zoomed(to: target, around: anchor)
    }
}
