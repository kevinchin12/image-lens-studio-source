import XCTest
@testable import ImageLensProviders

final class ReversePromptTemplateTests: XCTestCase {
    func testTemplateNamesEveryRequiredModuleAndBoundary() {
        let text = ReversePromptTemplate(includeChinese: false).text

        for kind in ReversePromptModuleKind.allCases {
            XCTAssertTrue(text.contains(kind.rawValue), "Missing module instruction for \(kind.rawValue)")
        }

        XCTAssertTrue(text.contains("OBSERVABLE / INFERRED BOUNDARY"))
        XCTAssertTrue(text.contains("directly grounded in visible pixels"))
        XCTAssertTrue(text.contains("not directly proven by pixels"))
        XCTAssertTrue(text.contains("Do not return Markdown"))
        XCTAssertTrue(text.contains(ReversePromptSchema.version))
    }

    func testTemplateMakesChineseOutputExplicit() {
        let englishOnly = ReversePromptTemplate(includeChinese: false).text
        XCTAssertTrue(englishOnly.contains("Set every promptChinese value to an empty string"))
        XCTAssertTrue(englishOnly.contains("keywords.chinese to an empty array"))

        let bilingual = ReversePromptTemplate(includeChinese: true).text
        XCTAssertTrue(bilingual.contains("faithful Chinese semantic translation"))
        XCTAssertTrue(bilingual.contains("with no added facts"))
    }

    func testTemplateRejectsIdentityAndEmptyPraise() {
        let text = ReversePromptTemplate(includeChinese: true).text

        XCTAssertTrue(text.contains("Never identify a real person"))
        XCTAssertTrue(text.contains("render engine"))
        XCTAssertTrue(text.contains("empty praise"))
        XCTAssertTrue(text.contains("rather than inventing it"))
    }
}
