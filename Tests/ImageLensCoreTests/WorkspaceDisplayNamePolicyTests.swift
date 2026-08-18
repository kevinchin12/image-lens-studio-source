import XCTest
@testable import ImageLensCore

final class WorkspaceDisplayNamePolicyTests: XCTestCase {
    func testDefaultNamesAdvancePastHighestUsedOrdinal() {
        XCTAssertEqual(
            WorkspaceDisplayNamePolicy.nextDefaultName(
                for: .generator,
                existingNames: ["生图 1", "海报主视觉", "生图 3", "生图 3"]
            ),
            "生图 4"
        )
        XCTAssertEqual(
            WorkspaceDisplayNamePolicy.nextDefaultName(
                for: .generationGroup,
                existingNames: []
            ),
            "生成结果 1"
        )
    }

    func testCopyingDefaultNameUsesNextDefaultOrdinal() {
        XCTAssertEqual(
            WorkspaceDisplayNamePolicy.copiedName(
                from: "生图 1",
                for: .generator,
                existingNames: ["生图 1"]
            ),
            "生图 2"
        )
    }

    func testCopyingCustomNameUsesCompactCopySuffix() {
        XCTAssertEqual(
            WorkspaceDisplayNamePolicy.copiedName(
                from: "海报主视觉",
                for: .generator,
                existingNames: ["海报主视觉"]
            ),
            "海报主视觉 副本"
        )
        XCTAssertEqual(
            WorkspaceDisplayNamePolicy.copiedName(
                from: "海报主视觉 副本",
                for: .generator,
                existingNames: ["海报主视觉", "海报主视觉 副本"]
            ),
            "海报主视觉 副本 2"
        )
        XCTAssertEqual(
            WorkspaceDisplayNamePolicy.copiedName(
                from: "海报主视觉 副本 2",
                for: .generator,
                existingNames: ["海报主视觉 副本", "海报主视觉 副本 2"]
            ),
            "海报主视觉 副本 3"
        )
    }

    func testNormalizationTrimsOnlyOuterWhitespace() {
        XCTAssertEqual(
            WorkspaceDisplayNamePolicy.normalized("  主视觉 A  \n"),
            "主视觉 A"
        )
    }
}
