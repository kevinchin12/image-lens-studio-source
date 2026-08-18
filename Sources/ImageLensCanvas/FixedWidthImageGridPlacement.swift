import Foundation
import ImageLensCore

/// Pure placement policy for image nodes whose visible pixel width should stay
/// constant while their canvas height follows the source image aspect ratio.
public struct FixedWidthImageGridPlacement: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public var assetID: AssetID
        public var pixelSize: PixelSize?

        public init(assetID: AssetID, pixelSize: PixelSize?) {
            self.assetID = assetID
            self.pixelSize = pixelSize
        }
    }

    public var targetWidth: Double
    public var fallbackHeight: Double

    public init(
        targetWidth: Double = 320,
        fallbackHeight: Double = 240
    ) {
        precondition(targetWidth.isFinite && targetWidth > 0, "Target width must be positive")
        precondition(fallbackHeight.isFinite && fallbackHeight > 0, "Fallback height must be positive")
        self.targetWidth = targetWidth
        self.fallbackHeight = fallbackHeight
    }

    public func size(for pixelSize: PixelSize?) -> WorldSize {
        guard let pixelSize,
              pixelSize.width > 0,
              pixelSize.height > 0 else {
            return WorldSize(width: targetWidth, height: fallbackHeight)
        }
        return WorldSize(
            width: targetWidth,
            height: targetWidth * Double(pixelSize.height) / Double(pixelSize.width)
        )
    }

    /// Places images left-to-right in rows. Every row advances by its tallest
    /// image, so mixed aspect ratios preserve the requested vertical gap.
    public func place(
        _ items: [Item],
        startingAt origin: WorldPoint,
        columns: Int,
        gap: WorldSize,
        existingNodes: [CanvasNode] = [],
        createdAt: Date = .now
    ) -> [CanvasNode] {
        guard !items.isEmpty else { return [] }
        precondition(gap.width.isFinite && gap.width >= 0, "Horizontal gap cannot be negative")
        precondition(gap.height.isFinite && gap.height >= 0, "Vertical gap cannot be negative")

        let safeColumns = max(1, columns)
        let sizes = items.map { size(for: $0.pixelSize) }
        let rowCount = (items.count + safeColumns - 1) / safeColumns
        let rowHeights = (0 ..< rowCount).map { row in
            let lowerBound = row * safeColumns
            let upperBound = min(lowerBound + safeColumns, sizes.count)
            return sizes[lowerBound ..< upperBound].map(\.height).max() ?? fallbackHeight
        }

        var rowOrigins = Array(repeating: origin.y, count: rowCount)
        for row in 1 ..< rowCount {
            rowOrigins[row] = rowOrigins[row - 1] + rowHeights[row - 1] + gap.height
        }

        let firstZIndex = (existingNodes.map(\.zIndex).max() ?? -1) + 1
        return items.enumerated().map { index, item in
            let column = index % safeColumns
            let row = index / safeColumns
            return CanvasNode(
                imageAssetID: item.assetID,
                frame: WorldRect(
                    origin: WorldPoint(
                        x: origin.x + Double(column) * (targetWidth + gap.width),
                        y: rowOrigins[row]
                    ),
                    size: sizes[index]
                ),
                zIndex: firstZIndex + index,
                createdAt: createdAt
            )
        }
    }
}
