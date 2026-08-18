import Foundation
import ImageLensCore

/// Deterministic defaults for creating persisted canvas nodes without UI types.
public struct CanvasNodePlacementPolicy: Sendable {
    public var imageSize: WorldSize
    public var moduleSize: WorldSize
    public var textSize: WorldSize
    public var recipeSize: WorldSize
    public var generationSize: WorldSize
    public var cascadeOffset: WorldSize

    public init(
        imageSize: WorldSize = WorldSize(width: 320, height: 240),
        moduleSize: WorldSize = WorldSize(width: 280, height: 160),
        textSize: WorldSize = WorldSize(width: 280, height: 180),
        recipeSize: WorldSize = WorldSize(width: 320, height: 200),
        generationSize: WorldSize = WorldSize(
            width: GeneratorNodeLayoutPolicy.defaultWidth,
            height: GeneratorNodeLayoutPolicy.collapsedHeight
        ),
        cascadeOffset: WorldSize = WorldSize(width: 48, height: 48)
    ) {
        precondition(!imageSize.isEmpty, "Image node size must be positive")
        precondition(!moduleSize.isEmpty, "Module node size must be positive")
        precondition(!textSize.isEmpty, "Text node size must be positive")
        precondition(!recipeSize.isEmpty, "Recipe node size must be positive")
        precondition(!generationSize.isEmpty, "Generation node size must be positive")
        self.imageSize = imageSize
        self.moduleSize = moduleSize
        self.textSize = textSize
        self.recipeSize = recipeSize
        self.generationSize = generationSize
        self.cascadeOffset = cascadeOffset
    }

    public static let studioDefault = CanvasNodePlacementPolicy()

    private var layoutRegistry: CanvasNodeLayoutRegistry {
        CanvasNodeLayoutRegistry(
            descriptors: [
                .image: customizedDescriptor(for: .image, defaultSize: imageSize),
                .module: customizedDescriptor(for: .module, defaultSize: moduleSize),
                .text: customizedDescriptor(for: .text, defaultSize: textSize),
                .recipe: customizedDescriptor(for: .recipe, defaultSize: recipeSize),
                .generation: customizedDescriptor(for: .generation, defaultSize: generationSize)
            ]
        )
    }

    public func defaultSize(for kind: CanvasNodeKind) -> WorldSize {
        layoutRegistry.descriptor(for: kind).defaultSize
    }

    private func customizedDescriptor(
        for kind: CanvasNodeKind,
        defaultSize: WorldSize
    ) -> CanvasNodeLayoutDescriptor {
        var descriptor = CanvasNodeLayoutRegistry.studioDefault.descriptor(for: kind)
        descriptor.defaultSize = defaultSize
        return descriptor
    }

    public func makeNode(
        kind: CanvasNodeKind,
        entityID: UUID,
        at origin: WorldPoint,
        zIndex: Int = 0,
        createdAt: Date = .now
    ) -> CanvasNode {
        CanvasNode(
            kind: kind,
            entityID: entityID,
            frame: WorldRect(origin: origin, size: defaultSize(for: kind)),
            zIndex: zIndex,
            createdAt: createdAt
        )
    }

    /// Places a batch with visible diagonal offsets. Occupied cascade origins
    /// are skipped, making repeated imports at the same pointer location useful.
    public func place(
        kind: CanvasNodeKind,
        entityIDs: [UUID],
        startingAt origin: WorldPoint,
        existingNodes: [CanvasNode] = [],
        createdAt: Date = .now
    ) -> [CanvasNode] {
        guard !entityIDs.isEmpty else { return [] }

        var occupiedOrigins = Set(existingNodes.map { $0.frame.standardized.origin })
        var cascadeIndex = 0
        var nextZIndex = (existingNodes.map(\.zIndex).max() ?? -1) + 1
        var result: [CanvasNode] = []
        result.reserveCapacity(entityIDs.count)

        for entityID in entityIDs {
            var candidateOrigin: WorldPoint
            repeat {
                candidateOrigin = WorldPoint(
                    x: origin.x + Double(cascadeIndex) * cascadeOffset.width,
                    y: origin.y + Double(cascadeIndex) * cascadeOffset.height
                )
                cascadeIndex += 1
            } while occupiedOrigins.contains(candidateOrigin)

            let node = makeNode(
                kind: kind,
                entityID: entityID,
                at: candidateOrigin,
                zIndex: nextZIndex,
                createdAt: createdAt
            )
            result.append(node)
            occupiedOrigins.insert(candidateOrigin)
            nextZIndex += 1
        }
        return result
    }

    public func placeImportedImages(
        _ assetIDs: [AssetID],
        startingAt origin: WorldPoint,
        existingNodes: [CanvasNode] = [],
        createdAt: Date = .now
    ) -> [CanvasNode] {
        place(
            kind: .image,
            entityIDs: assetIDs.map(\.rawValue),
            startingAt: origin,
            existingNodes: existingNodes,
            createdAt: createdAt
        )
    }
}
