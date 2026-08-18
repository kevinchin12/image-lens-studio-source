import Foundation
import XCTest
@testable import ImageLensProviders

final class ReversePromptSchemaTests: XCTestCase {
    func testStrictDecoderReturnsAllModulesInCompilerOrder() throws {
        let data = try encodedFixture(includeChinese: true)
        let response = try ReversePromptSchema.decode(data, includeChinese: true)

        XCTAssertEqual(response.schemaVersion, ReversePromptSchema.version)
        XCTAssertEqual(response.orderedModules.map(\.kind), ReversePromptModuleKind.allCases)
        XCTAssertEqual(response.modules.camera.evidence.map(\.kind), [.observable, .inferred])
        XCTAssertFalse(response.modules.subject.promptChinese.isEmpty)
    }

    func testStrictDecoderRejectsUnexpectedTopLevelKey() throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedFixture(includeChinese: false)) as? [String: Any]
        )
        object["explanation"] = "extra prose"
        let data = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try ReversePromptSchema.decode(data, includeChinese: false)) { error in
            guard case ReversePromptSchemaError.unexpectedKeys(let path, _, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(path, "$")
        }
    }

    func testStrictDecoderRejectsMissingVisualModule() throws {
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedFixture(includeChinese: false)) as? [String: Any]
        )
        var modules = try XCTUnwrap(root["modules"] as? [String: Any])
        modules.removeValue(forKey: "material")
        root["modules"] = modules
        let data = try JSONSerialization.data(withJSONObject: root)

        XCTAssertThrowsError(try ReversePromptSchema.decode(data, includeChinese: false)) { error in
            guard case ReversePromptSchemaError.unexpectedKeys(let path, _, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(path, "$.modules")
        }
    }

    func testEnglishOnlyContractRejectsChineseContent() throws {
        let data = try encodedFixture(includeChinese: true)

        XCTAssertThrowsError(try ReversePromptSchema.decode(data, includeChinese: false)) { error in
            guard case ReversePromptSchemaError.invalidValue(let path, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertTrue(path.hasSuffix(".promptChinese") || path == "$.keywords.chinese")
        }
    }

    func testChineseContractRejectsContentWithoutCanonicalEnglishModule() throws {
        var response = fixture(includeChinese: true)
        response.modules.environment.promptEnglish = ""
        response.modules.environment.evidence = []
        let data = try JSONEncoder().encode(response)

        XCTAssertThrowsError(try ReversePromptSchema.decode(data, includeChinese: true)) { error in
            guard case ReversePromptSchemaError.invalidValue(let path, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(path, "$.modules.environment.promptChinese")
        }
    }

    func testNonEmptyPromptRequiresEvidence() throws {
        var response = fixture(includeChinese: false)
        response.modules.subject.evidence = []
        let data = try JSONEncoder().encode(response)

        XCTAssertThrowsError(try ReversePromptSchema.decode(data, includeChinese: false)) { error in
            guard case ReversePromptSchemaError.invalidValue(let path, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(path, "$.modules.subject.evidence")
        }
    }

    func testUnknownEvidenceKindFailsTypedDecoding() throws {
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedFixture(includeChinese: false)) as? [String: Any]
        )
        var modules = try XCTUnwrap(root["modules"] as? [String: Any])
        var subject = try XCTUnwrap(modules["subject"] as? [String: Any])
        subject["evidence"] = [["kind": "guessed", "statement": "A person is visible."]]
        modules["subject"] = subject
        root["modules"] = modules
        let data = try JSONSerialization.data(withJSONObject: root)

        XCTAssertThrowsError(try ReversePromptSchema.decode(data, includeChinese: false)) { error in
            guard case ReversePromptSchemaError.decodingFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func encodedFixture(includeChinese: Bool) throws -> Data {
        try JSONEncoder().encode(fixture(includeChinese: includeChinese))
    }

    private func fixture(includeChinese: Bool) -> ReversePromptResponseDTO {
        let observed = ReversePromptEvidenceDTO(
            kind: .observable,
            statement: "A single red ceramic cup sits near the center."
        )
        let inferred = ReversePromptEvidenceDTO(
            kind: .inferred,
            statement: "The shallow depth appearance suggests a wide aperture."
        )

        func module(_ english: String, evidence: [ReversePromptEvidenceDTO] = [observed]) -> ReversePromptModuleDTO {
            ReversePromptModuleDTO(
                promptEnglish: english,
                promptChinese: includeChinese ? "红色陶瓷杯的视觉描述" : "",
                evidence: evidence
            )
        }

        return ReversePromptResponseDTO(
            title: "Red Cup Still Life",
            modules: ReversePromptModulesDTO(
                subject: module("single red ceramic cup"),
                style: module("minimal editorial still-life photography"),
                lighting: module("soft side light with a gentle shadow"),
                camera: module("close framing with shallow depth appearance", evidence: [observed, inferred]),
                environment: module("neutral tabletop against a plain background"),
                material: module("glossy ceramic surface"),
                composition: module("center-weighted composition with generous negative space"),
                rendering: module("clean photographic finish with restrained contrast")
            ),
            keywords: ReversePromptKeywordsDTO(
                english: ["red cup", "ceramic", "still life", "soft light", "minimal", "negative space"],
                chinese: includeChinese ? ["红杯", "陶瓷", "静物", "柔光", "极简", "留白"] : []
            )
        )
    }
}
