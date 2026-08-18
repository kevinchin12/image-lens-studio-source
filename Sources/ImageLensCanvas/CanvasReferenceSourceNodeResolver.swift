import Foundation
import ImageLensCore

/// Resolves the canvas occurrence that visually owns an asset-reference edge.
///
/// A copied image intentionally reuses its asset bytes and `AssetID`. Newer
/// bindings persist the occurrence selected during the drag; legacy bindings
/// fall back to the earliest occurrence so a later copy cannot steal an
/// already-visible edge merely by landing closer to its destination.
public enum CanvasReferenceSourceNodeResolver {
    public static func resolve(
        assetID: AssetID,
        preferredNodeID: CanvasNodeID?,
        among candidates: [CanvasNode]
    ) -> CanvasNode? {
        let imageNodes = candidates.filter { $0.imageAssetID == assetID }

        if let preferredNodeID,
           let preferred = imageNodes.first(where: { $0.id == preferredNodeID }) {
            return preferred
        }

        return imageNodes.min { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
        }
    }
}
