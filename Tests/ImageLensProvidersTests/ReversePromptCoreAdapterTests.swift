import Foundation
import ImageLensCore
import XCTest
@testable import ImageLensProviders

final class ReversePromptCoreAdapterTests: XCTestCase {
    func testAdapterPreservesOrderSourceAndConservativeEvidence() {
        let assetID = AssetID()
        let snapshotID = AnalysisSnapshotID()
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let response = responseFixture()

        let modules = response.makePromptModules(
            sourceAssetID: assetID,
            sourceAnalysisSnapshotID: snapshotID,
            timestamp: timestamp
        )

        XCTAssertEqual(modules.map(\.category), PromptModuleCategory.allCases)
        XCTAssertEqual(modules.first?.sourceAssetID, assetID)
        XCTAssertEqual(modules.first?.sourceAnalysisSnapshotID, snapshotID)
        XCTAssertEqual(modules.first?.createdAt, timestamp)
        XCTAssertEqual(modules.first?.evidence, .observable)
        let camera = modules.first(where: { $0.category == .camera })
        XCTAssertEqual(camera?.evidence, .inferred)
        XCTAssertEqual(camera?.evidenceClaims.map(\.kind), [.observable, .inferred])
        XCTAssertEqual(
            camera?.evidenceClaims.map(\.statement),
            ["Visible evidence.", "Qualified interpretation."]
        )
    }

    func testAdapterUsesChineseContentAndOmitsEmptyCategories() {
        var response = responseFixture()
        response.modules.material.promptEnglish = ""
        response.modules.material.promptChinese = ""
        response.modules.material.evidence = []

        let modules = response.makePromptModules(language: .chinese)

        XCTAssertEqual(modules.count, 7)
        XCTAssertFalse(modules.contains(where: { $0.category == .material }))
        XCTAssertEqual(modules.first?.content, "中文主体")
    }

    private func responseFixture() -> ReversePromptResponseDTO {
        let observed = ReversePromptEvidenceDTO(kind: .observable, statement: "Visible evidence.")
        let inferred = ReversePromptEvidenceDTO(kind: .inferred, statement: "Qualified interpretation.")

        func module(
            _ category: ReversePromptModuleKind,
            evidence: [ReversePromptEvidenceDTO] = [observed]
        ) -> ReversePromptModuleDTO {
            ReversePromptModuleDTO(
                promptEnglish: "\(category.rawValue) fragment",
                promptChinese: category == .subject ? "中文主体" : "中文\(category.rawValue)",
                evidence: evidence
            )
        }

        return ReversePromptResponseDTO(
            title: "Fixture",
            modules: ReversePromptModulesDTO(
                subject: module(.subject),
                style: module(.style),
                lighting: module(.lighting),
                camera: module(.camera, evidence: [observed, inferred]),
                environment: module(.environment),
                material: module(.material),
                composition: module(.composition),
                rendering: module(.rendering)
            ),
            keywords: ReversePromptKeywordsDTO(
                english: ["one", "two", "three", "four", "five", "six"],
                chinese: ["一", "二", "三", "四", "五", "六"]
            )
        )
    }
}
