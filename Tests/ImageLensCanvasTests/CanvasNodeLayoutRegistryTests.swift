import XCTest
import ImageLensCore
@testable import ImageLensCanvas

final class CanvasNodeLayoutRegistryTests: XCTestCase {
    func testRegistryCoversEveryPersistedKind() {
        let registry = CanvasNodeLayoutRegistry.studioDefault

        for kind in CanvasNodeKind.allCases {
            XCTAssertFalse(registry.descriptor(for: kind).defaultSize.isEmpty)
            XCTAssertFalse(registry.descriptor(for: kind).minimumSize.isEmpty)
        }
    }

    func testSharedRegistryPreservesExistingPlacementAndResizeTraits() {
        let registry = CanvasNodeLayoutRegistry.studioDefault
        let placement = CanvasNodePlacementPolicy.studioDefault

        for kind in CanvasNodeKind.allCases {
            let descriptor = registry.descriptor(for: kind)
            XCTAssertEqual(placement.defaultSize(for: kind), descriptor.defaultSize)
            XCTAssertEqual(
                CanvasNodeResizePolicy.standard(for: kind),
                CanvasNodeResizePolicy(
                    minimumSize: descriptor.minimumSize,
                    preservesAspectRatio: descriptor.preservesAspectRatio
                )
            )
        }
    }

    func testOnlyMediaPlacementPreservesAspectRatio() {
        let registry = CanvasNodeLayoutRegistry.studioDefault

        XCTAssertTrue(registry.descriptor(for: .image).preservesAspectRatio)
        XCTAssertFalse(registry.descriptor(for: .module).preservesAspectRatio)
        XCTAssertFalse(registry.descriptor(for: .text).preservesAspectRatio)
        XCTAssertFalse(registry.descriptor(for: .recipe).preservesAspectRatio)
        XCTAssertFalse(registry.descriptor(for: .generation).preservesAspectRatio)
    }
}
