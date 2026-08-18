import XCTest
@testable import ImageLensCore

final class AssetMediaKindTests: XCTestCase {
    func testMediaKindIsDerivedFromMIMETypeWithoutChangingPersistenceSchema() {
        let image = makeAsset(mimeType: " IMAGE/PNG ")
        let video = makeAsset(mimeType: "Video/MP4")
        let unknown = makeAsset(mimeType: "application/octet-stream")

        XCTAssertEqual(image.mediaKind, .image)
        XCTAssertTrue(image.isStillImage)
        XCTAssertTrue(image.supportsReversePrompt)
        XCTAssertTrue(image.supportsMediaReference)
        XCTAssertTrue(image.supportsReferenceBinding)

        XCTAssertEqual(video.mediaKind, .video)
        XCTAssertTrue(video.isVideo)
        XCTAssertFalse(video.supportsReversePrompt)
        XCTAssertTrue(video.supportsMediaReference)
        XCTAssertFalse(video.supportsReferenceBinding)

        XCTAssertEqual(unknown.mediaKind, .unknown)
        XCTAssertFalse(unknown.supportsReversePrompt)
        XCTAssertFalse(unknown.supportsMediaReference)
        XCTAssertFalse(unknown.supportsReferenceBinding)
    }

    func testGeneratedImageCanBeReferenceButCannotBeReversePrompted() {
        let asset = Asset(
            kind: .generated,
            displayName: "Result",
            relativePath: "assets/result.png",
            mimeType: "image/png"
        )

        XCTAssertFalse(asset.supportsReversePrompt)
        XCTAssertTrue(asset.supportsReferenceBinding)
    }

    private func makeAsset(mimeType: String) -> Asset {
        Asset(
            kind: .source,
            displayName: "Asset",
            relativePath: "assets/asset",
            mimeType: mimeType
        )
    }
}
