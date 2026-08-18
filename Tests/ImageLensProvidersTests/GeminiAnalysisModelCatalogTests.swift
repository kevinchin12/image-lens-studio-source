import XCTest
@testable import ImageLensProviders

final class GeminiAnalysisModelCatalogTests: XCTestCase {
    func testGemini37FlashIsTheDefaultAnalysisModel() throws {
        XCTAssertEqual(GeminiAnalysisModelCatalog.defaultModelID, "gemini-3.7-flash")
        XCTAssertEqual(
            GeminiProviderConfiguration().analysisModel,
            "gemini-3.7-flash"
        )

        let model = try XCTUnwrap(
            GeminiAnalysisModelCatalog.model(id: "gemini-3.7-flash")
        )
        XCTAssertEqual(model.displayName, "Gemini 3.7 Flash")
    }

    func testCatalogKeepsEarlierFlashModelsAvailable() {
        XCTAssertEqual(
            GeminiAnalysisModelCatalog.models.map(\.modelID),
            ["gemini-3.7-flash", "gemini-3.6-flash", "gemini-3.5-flash"]
        )
    }
}
