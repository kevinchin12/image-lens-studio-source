import Foundation
import ImageLensCore

/// Pure geometry for presenting generated image nodes as one collapsible group.
///
/// The group origin is its top-left corner. Expanded members are laid out
/// left-to-right below the header. Every member gets the same visible width,
/// while its height follows the aspect ratio of its existing canvas frame.
public struct GenerationGroupLayoutPolicy: Equatable, Sendable {
    public var memberWidth: Double
    public var fallbackMemberHeight: Double
    public var gap: WorldSize
    public var contentPadding: Double
    public var headerHeight: Double
    public var headerContentGap: Double
    public var memberTrailingChromeExtent: Double
    public var memberBottomChromeExtent: Double
    public var collapsedCardSize: WorldSize

    public init(
        memberWidth: Double = 320,
        fallbackMemberHeight: Double = 240,
        gap: WorldSize = WorldSize(width: 32, height: 32),
        contentPadding: Double = 24,
        headerHeight: Double = 44,
        headerContentGap: Double = 16,
        memberTrailingChromeExtent: Double = 0,
        memberBottomChromeExtent: Double = 0,
        collapsedCardSize: WorldSize = WorldSize(width: 320, height: 96)
    ) {
        precondition(memberWidth.isFinite && memberWidth > 0, "Member width must be positive")
        precondition(
            fallbackMemberHeight.isFinite && fallbackMemberHeight > 0,
            "Fallback member height must be positive"
        )
        precondition(
            gap.width.isFinite && gap.width >= 0
                && gap.height.isFinite && gap.height >= 0,
            "Group gaps cannot be negative"
        )
        precondition(
            contentPadding.isFinite && contentPadding >= 0,
            "Group padding cannot be negative"
        )
        precondition(headerHeight.isFinite && headerHeight > 0, "Header height must be positive")
        precondition(
            headerContentGap.isFinite && headerContentGap >= 0,
            "Header-to-content gap cannot be negative"
        )
        precondition(
            memberTrailingChromeExtent.isFinite && memberTrailingChromeExtent >= 0,
            "Member trailing chrome extent cannot be negative"
        )
        precondition(
            memberBottomChromeExtent.isFinite && memberBottomChromeExtent >= 0,
            "Member bottom chrome extent cannot be negative"
        )
        precondition(
            collapsedCardSize.width.isFinite && collapsedCardSize.width > 0
                && collapsedCardSize.height.isFinite && collapsedCardSize.height > 0,
            "Collapsed card size must be positive"
        )

        self.memberWidth = memberWidth
        self.fallbackMemberHeight = fallbackMemberHeight
        self.gap = gap
        self.contentPadding = contentPadding
        self.headerHeight = headerHeight
        self.headerContentGap = headerContentGap
        self.memberTrailingChromeExtent = memberTrailingChromeExtent
        self.memberBottomChromeExtent = memberBottomChromeExtent
        self.collapsedCardSize = collapsedCardSize
    }

    public func layout(
        members: [CanvasNode],
        origin: WorldPoint,
        columns: Int,
        isCollapsed: Bool
    ) -> GenerationGroupLayout {
        if isCollapsed {
            let bounds = WorldRect(origin: origin, size: collapsedCardSize)
            return GenerationGroupLayout(
                memberPlacements: [],
                bounds: bounds,
                headerFrame: headerFrame(in: bounds),
                contentFrame: .zero,
                isCollapsed: true
            )
        }

        let effectiveColumnCount = min(max(1, columns), max(1, members.count))
        let sizes = members.map { memberSize(for: $0.frame) }
        let rowCount = members.isEmpty
            ? 0
            : (members.count + effectiveColumnCount - 1) / effectiveColumnCount
        let rowHeights = (0 ..< rowCount).map { row in
            let lowerBound = row * effectiveColumnCount
            let upperBound = min(lowerBound + effectiveColumnCount, sizes.count)
            return sizes[lowerBound ..< upperBound].map(\.height).max() ?? fallbackMemberHeight
        }

        let gridWidth = members.isEmpty
            ? 0
            : Double(effectiveColumnCount) * memberWidth
                + Double(max(0, effectiveColumnCount - 1)) * gap.width
        let gridHeight = rowHeights.reduce(0, +)
            + Double(max(0, rowCount - 1)) * gap.height
        let boundsWidth = max(
            collapsedCardSize.width,
            gridWidth + memberTrailingChromeExtent + (2 * contentPadding)
        )
        let boundsHeight = members.isEmpty
            ? collapsedCardSize.height
            : contentPadding + headerHeight + headerContentGap
                + gridHeight + memberBottomChromeExtent + contentPadding
        let bounds = WorldRect(
            origin: origin,
            size: WorldSize(width: boundsWidth, height: boundsHeight)
        )
        let contentOrigin = WorldPoint(
            x: origin.x + contentPadding,
            y: origin.y + contentPadding + headerHeight + headerContentGap
        )

        var rowOrigins = Array(repeating: contentOrigin.y, count: rowCount)
        for row in 1 ..< rowCount {
            rowOrigins[row] = rowOrigins[row - 1] + rowHeights[row - 1] + gap.height
        }

        let placements = members.enumerated().map { index, member in
            let column = index % effectiveColumnCount
            let row = index / effectiveColumnCount
            return GenerationGroupLayout.MemberPlacement(
                nodeID: member.id,
                frame: WorldRect(
                    origin: WorldPoint(
                        x: contentOrigin.x + Double(column) * (memberWidth + gap.width),
                        y: rowOrigins[row]
                    ),
                    size: sizes[index]
                )
            )
        }
        let contentFrame = members.isEmpty
            ? WorldRect.zero
            : WorldRect(origin: contentOrigin, size: WorldSize(width: gridWidth, height: gridHeight))

        return GenerationGroupLayout(
            memberPlacements: placements,
            bounds: bounds,
            headerFrame: headerFrame(in: bounds),
            contentFrame: contentFrame,
            isCollapsed: false
        )
    }

    private func memberSize(for frame: WorldRect) -> WorldSize {
        let standardized = frame.standardized
        guard standardized.width > 0, standardized.height > 0 else {
            return WorldSize(width: memberWidth, height: fallbackMemberHeight)
        }
        return WorldSize(
            width: memberWidth,
            height: memberWidth * standardized.height / standardized.width
        )
    }

    private func headerFrame(in bounds: WorldRect) -> WorldRect {
        WorldRect(
            x: bounds.minX + contentPadding,
            y: bounds.minY + contentPadding,
            width: max(0, bounds.width - (2 * contentPadding)),
            height: min(headerHeight, max(0, bounds.height - (2 * contentPadding)))
        )
    }
}

public struct GenerationGroupLayout: Equatable, Sendable {
    public struct MemberPlacement: Equatable, Sendable {
        public let nodeID: CanvasNodeID
        public let frame: WorldRect

        public init(nodeID: CanvasNodeID, frame: WorldRect) {
            self.nodeID = nodeID
            self.frame = frame
        }
    }

    public let memberPlacements: [MemberPlacement]
    public let bounds: WorldRect
    public let headerFrame: WorldRect
    public let contentFrame: WorldRect
    public let isCollapsed: Bool

    public init(
        memberPlacements: [MemberPlacement],
        bounds: WorldRect,
        headerFrame: WorldRect,
        contentFrame: WorldRect,
        isCollapsed: Bool
    ) {
        self.memberPlacements = memberPlacements
        self.bounds = bounds
        self.headerFrame = headerFrame
        self.contentFrame = contentFrame
        self.isCollapsed = isCollapsed
    }

    public var memberFrames: [CanvasNodeID: WorldRect] {
        Dictionary(uniqueKeysWithValues: memberPlacements.map { ($0.nodeID, $0.frame) })
    }

    public func frame(for nodeID: CanvasNodeID) -> WorldRect? {
        memberPlacements.first { $0.nodeID == nodeID }?.frame
    }
}
