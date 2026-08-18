import Foundation
import ImageLensCore

public enum CanvasNodeResizeEdge: String, CaseIterable, Hashable, Sendable {
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
    case topLeft

    public var changesLeftEdge: Bool { self == .left || self == .topLeft || self == .bottomLeft }
    public var changesRightEdge: Bool { self == .right || self == .topRight || self == .bottomRight }
    public var changesTopEdge: Bool { self == .top || self == .topLeft || self == .topRight }
    public var changesBottomEdge: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }
    public var isHorizontalOnly: Bool { self == .left || self == .right }
    public var isVerticalOnly: Bool { self == .top || self == .bottom }
}

/// Pure world-space constraints for resizing a persisted canvas node from any
/// edge or corner. Pointer translations arrive in view points and are converted
/// through the current viewport scale.
public struct CanvasNodeResizePolicy: Equatable, Sendable {
    public var minimumSize: WorldSize
    public var preservesAspectRatio: Bool

    public init(minimumSize: WorldSize, preservesAspectRatio: Bool = false) {
        precondition(!minimumSize.isEmpty, "Resize minimum must be positive")
        self.minimumSize = minimumSize
        self.preservesAspectRatio = preservesAspectRatio
    }

    public static func standard(for kind: CanvasNodeKind) -> Self {
        let descriptor = CanvasNodeLayoutRegistry.studioDefault.descriptor(for: kind)
        return Self(
            minimumSize: descriptor.minimumSize,
            preservesAspectRatio: descriptor.preservesAspectRatio
        )
    }

    public func frame(
        from initialFrame: WorldRect,
        viewTranslation: ViewDragTranslation,
        viewportScale: Double,
        edge: CanvasNodeResizeEdge = .bottomRight
    ) -> WorldRect {
        guard viewportScale.isFinite, viewportScale > 0,
              viewTranslation.x.isFinite, viewTranslation.y.isFinite else {
            return initialFrame.standardized
        }

        let initial = initialFrame.standardized
        let worldX = viewTranslation.x / viewportScale
        let worldY = viewTranslation.y / viewportScale
        let proposedWidth = initial.width + (edge.changesLeftEdge ? -worldX : (edge.changesRightEdge ? worldX : 0))
        let proposedHeight = initial.height + (edge.changesTopEdge ? -worldY : (edge.changesBottomEdge ? worldY : 0))

        if preservesAspectRatio, initial.width > 0, initial.height > 0 {
            let widthScale = proposedWidth / initial.width
            let heightScale = proposedHeight / initial.height
            let requestedScale: Double
            if edge.isHorizontalOnly {
                requestedScale = widthScale
            } else if edge.isVerticalOnly {
                requestedScale = heightScale
            } else {
                requestedScale = abs(widthScale - 1) >= abs(heightScale - 1)
                    ? widthScale
                    : heightScale
            }
            let minimumScale = max(
                minimumSize.width / initial.width,
                minimumSize.height / initial.height
            )
            let scale = max(minimumScale, requestedScale)
            let size = WorldSize(
                width: initial.width * scale,
                height: initial.height * scale
            )
            return aspectPreservingFrame(
                initial: initial,
                size: size,
                edge: edge
            )
        }

        let size = WorldSize(
            width: max(minimumSize.width, proposedWidth),
            height: max(minimumSize.height, proposedHeight)
        )
        return WorldRect(
            origin: WorldPoint(
                x: edge.changesLeftEdge ? initial.maxX - size.width : initial.minX,
                y: edge.changesTopEdge ? initial.maxY - size.height : initial.minY
            ),
            size: size
        )
    }

    private func aspectPreservingFrame(
        initial: WorldRect,
        size: WorldSize,
        edge: CanvasNodeResizeEdge
    ) -> WorldRect {
        let x: Double
        if edge.changesLeftEdge {
            x = initial.maxX - size.width
        } else if edge.changesRightEdge {
            x = initial.minX
        } else {
            x = initial.minX + (initial.width - size.width) / 2
        }

        let y: Double
        if edge.changesTopEdge {
            y = initial.maxY - size.height
        } else if edge.changesBottomEdge {
            y = initial.minY
        } else {
            y = initial.minY + (initial.height - size.height) / 2
        }
        return WorldRect(origin: WorldPoint(x: x, y: y), size: size)
    }
}

/// Reversible persisted resize. The UI previews the candidate frame while the
/// pointer is down and commits one command on mouse-up, producing one undo step.
public struct CanvasNodeResizeCommand: Hashable, Sendable {
    public let nodeID: CanvasNodeID
    public let fromFrame: WorldRect
    public let toFrame: WorldRect

    public init(nodeID: CanvasNodeID, fromFrame: WorldRect, toFrame: WorldRect) {
        self.nodeID = nodeID
        self.fromFrame = fromFrame.standardized
        self.toFrame = toFrame.standardized
    }

    public var isNoOp: Bool { fromFrame == toFrame }

    public var inverse: Self {
        Self(nodeID: nodeID, fromFrame: toFrame, toFrame: fromFrame)
    }

    public func applying(to node: CanvasNode) -> CanvasNode? {
        guard node.id == nodeID else { return nil }
        var result = node
        result.frame = toFrame
        return result
    }

    @discardableResult
    public func apply(to nodes: inout [CanvasNode]) -> Bool {
        guard let index = nodes.firstIndex(where: { $0.id == nodeID }) else { return false }
        nodes[index].frame = toFrame
        return true
    }
}
