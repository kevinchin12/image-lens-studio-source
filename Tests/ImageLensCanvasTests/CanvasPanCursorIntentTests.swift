import XCTest
@testable import ImageLensCanvas

final class CanvasPanCursorIntentTests: XCTestCase {
    func testSpaceImmediatelySelectsOpenHandAndReleaseRestoresDefault() {
        XCTAssertEqual(
            CanvasPanCursorIntent(
                isSpacePanToolActive: true,
                isDraggingCanvas: false
            ),
            .openHand
        )
        XCTAssertEqual(
            CanvasPanCursorIntent(
                isSpacePanToolActive: false,
                isDraggingCanvas: false
            ),
            .systemDefault
        )
    }

    func testActiveCanvasDragAlwaysUsesClosedHand() {
        XCTAssertEqual(
            CanvasPanCursorIntent(
                isSpacePanToolActive: true,
                isDraggingCanvas: true
            ),
            .closedHand
        )
        XCTAssertEqual(
            CanvasPanCursorIntent(
                isSpacePanToolActive: false,
                isDraggingCanvas: true
            ),
            .closedHand
        )
    }

    func testCanvasKeyboardOwnershipUsesFirstResponderAfterEditingEnds() {
        XCTAssertTrue(
            CanvasKeyboardRoutingContext(
                isCanvasFirstResponder: true,
                textResponderRole: .none
            ).canvasOwnsKeyboardInput
        )
        XCTAssertFalse(
            CanvasKeyboardRoutingContext(
                isCanvasFirstResponder: false,
                textResponderRole: .none
            ).canvasOwnsKeyboardInput
        )
        XCTAssertFalse(
            CanvasKeyboardRoutingContext(
                isCanvasFirstResponder: false,
                textResponderRole: .none
            ).windowOwnsCanvasCommands
        )
        XCTAssertTrue(
            CanvasKeyboardRoutingContext(
                isCanvasFirstResponder: true,
                textResponderRole: .none
            ).windowOwnsCanvasCommands
        )
    }

    func testNonCanvasNonTextResponderDoesNotOwnCanvasCommands() {
        let sidebarOrToolbarContext = CanvasKeyboardRoutingContext(
            isCanvasFirstResponder: false,
            textResponderRole: .none
        )

        XCTAssertFalse(sidebarOrToolbarContext.canvasOwnsKeyboardInput)
        XCTAssertFalse(sidebarOrToolbarContext.windowOwnsCanvasCommands)
    }

    func testActiveTextResponderKeepsTextCommandsInsideTextSystem() {
        XCTAssertFalse(
            CanvasKeyboardRoutingContext(
                isCanvasFirstResponder: true,
                textResponderRole: .editable
            ).canvasOwnsKeyboardInput
        )
        XCTAssertFalse(
            CanvasKeyboardRoutingContext(
                isCanvasFirstResponder: false,
                textResponderRole: .editable
            ).windowOwnsCanvasCommands
        )
        XCTAssertFalse(
            CanvasKeyboardRoutingContext(
                isCanvasFirstResponder: true,
                textResponderRole: .selectable
            ).windowOwnsCanvasCommands
        )
    }
}
