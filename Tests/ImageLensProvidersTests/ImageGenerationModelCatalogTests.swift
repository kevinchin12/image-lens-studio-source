import XCTest
@testable import ImageLensProviders

final class ImageGenerationModelCatalogTests: XCTestCase {
    func testGeminiCatalogExposesOnlyCurrentStableModels() {
        XCTAssertEqual(
            ImageGenerationModelCatalog.geminiModels.map(\.modelID),
            [
                "gemini-3.1-flash-lite-image",
                "gemini-3.1-flash-image",
                "gemini-3-pro-image"
            ]
        )
        XCTAssertEqual(
            ImageGenerationModelCatalog.gemini.defaultModelID,
            "gemini-3.1-flash-image"
        )
        XCTAssertTrue(ImageGenerationModelCatalog.geminiModels.allSatisfy { $0.lifecycle == .stable })
    }

    func testCatalogProvidesCapabilitiesWithoutRejectingUnknownStoredModels() {
        let pro = ImageGenerationModelCatalog.model(
            providerID: "gemini",
            modelID: "gemini-3-pro-image"
        )
        XCTAssertEqual(pro?.supportedImageSizes, ["1K", "2K", "4K"])
        XCTAssertEqual(pro?.maxReferenceImages, 14)
        XCTAssertEqual(pro?.supportedReferenceMediaKinds, [.image])
        XCTAssertNil(
            ImageGenerationModelCatalog.model(
                providerID: "future-provider",
                modelID: "custom-model"
            )
        )
    }

    func testGeminiReferenceMediaCapabilitiesAreModelSpecific() throws {
        let lite = try XCTUnwrap(
            ImageGenerationModelCatalog.model(
                providerID: "gemini",
                modelID: "gemini-3.1-flash-lite-image"
            )
        )
        let flash = try XCTUnwrap(
            ImageGenerationModelCatalog.model(
                providerID: "gemini",
                modelID: "gemini-3.1-flash-image"
            )
        )
        let pro = try XCTUnwrap(
            ImageGenerationModelCatalog.model(
                providerID: "gemini",
                modelID: "gemini-3-pro-image"
            )
        )

        XCTAssertEqual(lite.supportedReferenceMediaKinds, [.image, .video])
        XCTAssertEqual(flash.supportedReferenceMediaKinds, [.image, .video])
        XCTAssertEqual(pro.supportedReferenceMediaKinds, [.image])
    }
}
