import Foundation
import ImageLensCore

/// Canvas-only layout traits kept separate from the semantic node registry.
/// This is the single mapping used by both placement and resizing policies.
public struct CanvasNodeLayoutDescriptor: Equatable, Sendable {
    public var defaultSize: WorldSize
    public var minimumSize: WorldSize
    public var preservesAspectRatio: Bool

    public init(
        defaultSize: WorldSize,
        minimumSize: WorldSize,
        preservesAspectRatio: Bool = false
    ) {
        precondition(!defaultSize.isEmpty, "Default node size must be positive")
        precondition(!minimumSize.isEmpty, "Minimum node size must be positive")
        self.defaultSize = defaultSize
        self.minimumSize = minimumSize
        self.preservesAspectRatio = preservesAspectRatio
    }
}

public struct CanvasNodeLayoutRegistry: Equatable, Sendable {
    private var descriptors: [CanvasNodeKind: CanvasNodeLayoutDescriptor]

    public init(descriptors: [CanvasNodeKind: CanvasNodeLayoutDescriptor]) {
        precondition(
            CanvasNodeKind.allCases.allSatisfy { descriptors[$0] != nil },
            "Every persisted canvas node kind needs layout traits"
        )
        self.descriptors = descriptors
    }

    public func descriptor(for kind: CanvasNodeKind) -> CanvasNodeLayoutDescriptor {
        // The initializer guarantees total coverage of the finite persisted enum.
        descriptors[kind]!
    }

    public static let studioDefault = CanvasNodeLayoutRegistry(
        descriptors: [
            .image: CanvasNodeLayoutDescriptor(
                defaultSize: WorldSize(width: 320, height: 240),
                minimumSize: WorldSize(width: 120, height: 90),
                preservesAspectRatio: true
            ),
            .module: CanvasNodeLayoutDescriptor(
                defaultSize: WorldSize(width: 280, height: 160),
                minimumSize: WorldSize(width: 220, height: 120)
            ),
            .text: CanvasNodeLayoutDescriptor(
                defaultSize: WorldSize(width: 280, height: 180),
                minimumSize: WorldSize(width: 200, height: 120)
            ),
            .recipe: CanvasNodeLayoutDescriptor(
                defaultSize: WorldSize(width: 320, height: 200),
                minimumSize: WorldSize(width: 240, height: 160)
            ),
            .generation: CanvasNodeLayoutDescriptor(
                defaultSize: WorldSize(
                    width: GeneratorNodeLayoutPolicy.defaultWidth,
                    height: GeneratorNodeLayoutPolicy.collapsedHeight
                ),
                minimumSize: WorldSize(
                    width: GeneratorNodeLayoutPolicy.minimumWidth,
                    height: GeneratorNodeLayoutPolicy.collapsedHeight
                )
            )
        ]
    )
}
