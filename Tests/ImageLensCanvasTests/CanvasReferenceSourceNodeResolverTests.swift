import ImageLensCanvas
import ImageLensCore
import XCTest

final class CanvasReferenceSourceNodeResolverTests: XCTestCase {
    func testPreferredOccurrenceWinsOverNewerCopiedImage() throws {
        let assetID = AssetID()
        let original = imageNode(
            assetID: assetID,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let copy = imageNode(
            assetID: assetID,
            createdAt: Date(timeIntervalSince1970: 200)
        )

        let resolved = CanvasReferenceSourceNodeResolver.resolve(
            assetID: assetID,
            preferredNodeID: original.id,
            among: [copy, original]
        )

        XCTAssertEqual(resolved?.id, original.id)
    }

    func testLegacyBindingFallsBackToEarliestOccurrenceInsteadOfCanvasPosition() throws {
        let assetID = AssetID()
        let original = imageNode(
            assetID: assetID,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let laterCopy = imageNode(
            assetID: assetID,
            createdAt: Date(timeIntervalSince1970: 200)
        )

        let resolved = CanvasReferenceSourceNodeResolver.resolve(
            assetID: assetID,
            preferredNodeID: nil,
            among: [laterCopy, original]
        )

        XCTAssertEqual(resolved?.id, original.id)
    }

    private func imageNode(assetID: AssetID, createdAt: Date) -> CanvasNode {
        CanvasNode(
            imageAssetID: assetID,
            frame: WorldRect(x: 0, y: 0, width: 420, height: 320),
            createdAt: createdAt
        )
    }
}
