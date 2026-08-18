import ImageLensCore

/// Pure canvas geometry for image pixels and the lightweight controls arranged
/// around them. The persisted image frame remains stable for storage and
/// selection; visible graph anchors follow the aspect-fitted image pixels.
public struct ImageNodeSurroundLayout: Equatable, Sendable {
    public static let defaultTopRailHeight = 24.0
    public static let defaultSummaryHeight = 42.0
    public static let defaultRailGap = 5.0
    public static let defaultTagGap = 8.0
    /// Includes the 58-point tag, a gap, and the selected-bundle output handle.
    public static let defaultTagWidth = 110.0
    public static let defaultTagStackHeight = 230.0

    public let persistedImageFrame: WorldRect
    public let displayedImageFrame: WorldRect
    public let headerFrame: WorldRect
    public let summaryFrame: WorldRect
    public let tagLaneFrame: WorldRect
    public let shellFrame: WorldRect
    public let includesHeaderChrome: Bool
    public let includesAnalysisChrome: Bool
    public let includesStructuredPromptChrome: Bool

    public var leadingImageConnectionAnchor: WorldPoint {
        WorldPoint(
            x: displayedImageFrame.minX,
            y: displayedImageFrame.minY + displayedImageFrame.height / 2
        )
    }

    public var trailingImageConnectionAnchor: WorldPoint {
        WorldPoint(
            x: displayedImageFrame.maxX,
            y: displayedImageFrame.minY + displayedImageFrame.height / 2
        )
    }

    public init(
        imageFrame: WorldRect,
        contentAspectRatio: Double?,
        includesHeaderChrome: Bool = true,
        includesAnalysisChrome: Bool = true,
        includesStructuredPromptChrome: Bool? = nil,
        topRailHeight: Double = Self.defaultTopRailHeight,
        summaryHeight: Double = Self.defaultSummaryHeight,
        railGap: Double = Self.defaultRailGap,
        tagGap: Double = Self.defaultTagGap,
        tagWidth: Double = Self.defaultTagWidth,
        tagStackHeight: Double = Self.defaultTagStackHeight
    ) {
        let imageFrame = imageFrame.standardized
        let includesStructuredPromptChrome = includesStructuredPromptChrome
            ?? includesAnalysisChrome
        let displayedImageFrame = Self.aspectFit(
            aspectRatio: contentAspectRatio,
            inside: imageFrame
        )
        let headerFrame = includesHeaderChrome
            ? WorldRect(
                x: displayedImageFrame.minX,
                y: displayedImageFrame.minY - railGap - topRailHeight,
                width: displayedImageFrame.width,
                height: topRailHeight
            )
            : .zero
        let summaryFrame: WorldRect
        let tagLaneFrame: WorldRect
        if includesAnalysisChrome {
            summaryFrame = WorldRect(
                x: displayedImageFrame.minX,
                y: displayedImageFrame.maxY + railGap,
                width: displayedImageFrame.width,
                height: summaryHeight
            )
        } else {
            summaryFrame = .zero
        }
        if includesStructuredPromptChrome {
            tagLaneFrame = WorldRect(
                x: displayedImageFrame.maxX + tagGap,
                y: displayedImageFrame.minY + (displayedImageFrame.height - tagStackHeight) / 2,
                width: tagWidth,
                height: tagStackHeight
            )
        } else {
            tagLaneFrame = .zero
        }

        // This envelope is intentionally independent of the loaded image's
        // aspect ratio. The parent can position the node before image decoding,
        // while the inner content can adopt its true ratio without shifting the
        // persisted graph node or being clipped.
        let headerTopExtent = includesHeaderChrome ? topRailHeight + railGap : 0
        let analysisTopExtent = includesStructuredPromptChrome
            ? max(0, (tagStackHeight - imageFrame.height) / 2)
            : 0
        let topExtent = max(headerTopExtent, analysisTopExtent)
        let summaryBottomExtent = includesAnalysisChrome ? summaryHeight + railGap : 0
        let tagBottomExtent = includesStructuredPromptChrome
            ? max(0, (tagStackHeight - imageFrame.height) / 2)
            : 0
        let bottomExtent = max(summaryBottomExtent, tagBottomExtent)
        let shellFrame = WorldRect(
            x: imageFrame.minX,
            y: imageFrame.minY - topExtent,
            width: imageFrame.width + (includesStructuredPromptChrome ? tagGap + tagWidth : 0),
            height: imageFrame.height + topExtent + bottomExtent
        )

        self.persistedImageFrame = imageFrame
        self.displayedImageFrame = displayedImageFrame
        self.headerFrame = headerFrame
        self.summaryFrame = summaryFrame
        self.tagLaneFrame = tagLaneFrame
        self.shellFrame = shellFrame
        self.includesHeaderChrome = includesHeaderChrome
        self.includesAnalysisChrome = includesAnalysisChrome
        self.includesStructuredPromptChrome = includesStructuredPromptChrome
    }

    private static func aspectFit(
        aspectRatio: Double?,
        inside container: WorldRect
    ) -> WorldRect {
        guard let aspectRatio,
              aspectRatio.isFinite,
              aspectRatio > 0,
              !container.isEmpty else { return container }

        let containerAspectRatio = container.width / container.height
        let width: Double
        let height: Double
        if aspectRatio >= containerAspectRatio {
            width = container.width
            height = width / aspectRatio
        } else {
            height = container.height
            width = height * aspectRatio
        }
        return WorldRect(
            x: container.minX + (container.width - width) / 2,
            y: container.minY + (container.height - height) / 2,
            width: width,
            height: height
        )
    }
}
