import Foundation

/// World-space geometry for the generator node's sectioned layout. Keeping
/// these values in one pure policy prevents controls from being squeezed by
/// incidental stack changes and gives persisted nodes one migration floor.
public struct GeneratorNodeLayoutPolicy: Equatable, Sendable {
    public static let horizontalPadding = 8.0
    public static let defaultWidth = 440.0
    public static let minimumWidth = 380.0
    public static let collapsedHeight = 426.0
    public static let previousCollapsedHeight = 560.0
    public static let controlHeight = 26.0
    public static let inputRowHeight = 26.0
    /// Matches the default generator content width at 16:9 so the empty and
    /// wide-result stages keep the same inset on the top and both sides.
    public static let mediaStageHeight = (defaultWidth - horizontalPadding * 2) * 9 / 16
    public static let referenceStripHeight = 44.0
    public static let footerHeight = 38.0
    public static let outputThumbnailHeight = 54.0
    public static let outputBatchSpacing = 8.0
    public static let outputShelfSpacing = 10.0
    public static let imageEditSummaryHeight = 34.0
    public static let imageEditSummarySpacing = 7.0
    public static let outputReferenceHandleGutterWidth = 36.0
    public static let outputReferenceHandleDiameter = 18.0
    public static let outputReferenceHandleHitDiameter = 26.0
    public static let outputReferenceHandleGap = 14.0
    public static let referenceAnchorY = 264.0
    public static let inputAnchorY = 316.0

    public let nodeWidth: Double

    public init(nodeWidth: Double) {
        self.nodeWidth = nodeWidth
    }

    public var contentWidth: Double {
        max(1, nodeWidth - Self.horizontalPadding * 2)
    }

    public static func normalizedHeight(_ height: Double) -> Double {
        guard height.isFinite else { return collapsedHeight }
        if abs(height - previousCollapsedHeight) <= 0.5 {
            return collapsedHeight
        }
        return max(height, collapsedHeight)
    }

    public static func outputShelfHeight(batchCount: Int) -> Double {
        guard batchCount > 0 else { return 0 }
        return outputThumbnailHeight + outputShelfSpacing
    }

    public static var imageEditSupplementaryHeight: Double {
        imageEditSummaryHeight + imageEditSummarySpacing
    }

    /// The result rail is derived chrome rather than persisted canvas content.
    /// Keeping its world-space rectangle here prevents the rail, shell, and
    /// body from drifting when canvas padding or thumbnail metrics change.
    public static func outputRailFrame(
        around nodeFrame: WorldRect,
        outputBatchCount: Int
    ) -> WorldRect? {
        guard outputBatchCount > 0 else { return nil }
        return WorldRect(
            x: nodeFrame.minX + horizontalPadding,
            y: nodeFrame.minY - outputShelfHeight(batchCount: outputBatchCount),
            width: max(1, nodeFrame.width - horizontalPadding * 2),
            height: outputThumbnailHeight
        )
    }

    public static func shellFrame(around nodeFrame: WorldRect, outputBatchCount: Int) -> WorldRect {
        let shelfHeight = outputShelfHeight(batchCount: outputBatchCount)
        let handleGutter = outputBatchCount > 0 ? outputReferenceHandleGutterWidth : 0
        return WorldRect(
            x: nodeFrame.minX,
            y: nodeFrame.minY - shelfHeight,
            width: nodeFrame.width + handleGutter,
            height: nodeFrame.height + shelfHeight
        )
    }

    /// The fitted image viewport inside the generator body. Keeping this in
    /// the shared layout policy lets persistent reference lines terminate at
    /// the same edge as the visible generated image for every aspect ratio.
    public static func mediaContentFrame(
        in nodeFrame: WorldRect,
        contentAspectRatio: Double?
    ) -> WorldRect {
        let stageHeight = fittedMediaStageHeight(
            nodeWidth: nodeFrame.width,
            contentAspectRatio: contentAspectRatio
        )
        let available = WorldRect(
            x: nodeFrame.minX + horizontalPadding,
            y: nodeFrame.minY + horizontalPadding,
            width: max(1, nodeFrame.width - horizontalPadding * 2),
            height: stageHeight
        )
        let ratio = normalizedAspectRatio(contentAspectRatio)
        let width: Double
        let height: Double
        let candidateHeight = available.width / ratio
        if candidateHeight <= available.height {
            width = available.width
            height = candidateHeight
        } else {
            height = available.height
            width = available.height * ratio
        }
        return WorldRect(
            x: available.minX + (available.width - width) / 2,
            y: available.minY,
            width: width,
            height: height
        )
    }

    /// Uses the selected media ratio to remove unused vertical stage space.
    /// The maximum keeps square and portrait results from taking over the
    /// whole generator, while wide results sit directly above the inputs.
    public static func fittedMediaStageHeight(
        nodeWidth: Double,
        contentAspectRatio: Double?
    ) -> Double {
        let contentWidth = max(1, nodeWidth - horizontalPadding * 2)
        let ratio = normalizedAspectRatio(contentAspectRatio)
        return min(mediaStageHeight, contentWidth / ratio)
    }

    public static func mediaReferenceAnchor(
        in nodeFrame: WorldRect,
        contentAspectRatio: Double?
    ) -> WorldPoint {
        let frame = mediaContentFrame(
            in: nodeFrame,
            contentAspectRatio: contentAspectRatio
        )
        return WorldPoint(
            x: frame.maxX,
            y: frame.minY + frame.height / 2
        )
    }

    /// The node-edge anchor used while the contextual output handle is hidden.
    /// Its vertical position follows the displayed image, while its horizontal
    /// position stays fixed to the generator body for every output ratio.
    public static func outputReferenceNodeEdgeAnchor(
        in nodeFrame: WorldRect,
        contentAspectRatio: Double?
    ) -> WorldPoint {
        let imageAnchor = mediaReferenceAnchor(
            in: nodeFrame,
            contentAspectRatio: contentAspectRatio
        )
        return WorldPoint(x: nodeFrame.maxX, y: imageAnchor.y)
    }

    /// The visible center of the generated-output reference handle. Its X
    /// position is fixed outside the generator body; only Y follows the
    /// displayed image so portrait and square results never pull it inward.
    public static func outputReferenceHandleCenter(
        in nodeFrame: WorldRect,
        contentAspectRatio: Double?
    ) -> WorldPoint {
        let imageAnchor = mediaReferenceAnchor(
            in: nodeFrame,
            contentAspectRatio: contentAspectRatio
        )
        return WorldPoint(
            x: nodeFrame.maxX + outputReferenceHandleGap + outputReferenceHandleDiameter / 2,
            y: imageAnchor.y
        )
    }

    private static func normalizedAspectRatio(_ value: Double?) -> Double {
        guard let value, value.isFinite, value > 0 else { return 16.0 / 9.0 }
        return value
    }
}
