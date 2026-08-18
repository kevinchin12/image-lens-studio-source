import XCTest
@testable import ImageLensMac
import ImageLensCanvas

final class GeneratorPromptLayoutTests: XCTestCase {
    func testImageEditSupplementaryContentAddsItsFullHeightToGenerator() {
        let baseLayout = GeneratorPromptLayout(
            prompt: "换成一把枪",
            nodeWidth: 440,
            baseNodeHeight: 426
        )
        let imageEditLayout = GeneratorPromptLayout(
            prompt: "换成一把枪",
            nodeWidth: 440,
            baseNodeHeight: 426 + GeneratorNodeLayoutPolicy.imageEditSupplementaryHeight
        )

        XCTAssertEqual(
            imageEditLayout.requiredNodeHeight - baseLayout.requiredNodeHeight,
            GeneratorNodeLayoutPolicy.imageEditSupplementaryHeight,
            accuracy: 0.000_001
        )
    }
}
