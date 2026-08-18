import AppKit
import XCTest
@testable import ImageLensMac

final class SemanticMaskCompositorTests: XCTestCase {
    func testCompositePreservesSourceOutsideMaskAndUsesGeneratedImageInsideMask() throws {
        let source = try png(colors: [
            NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1),
            NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1),
        ])
        let generated = try png(colors: [
            NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1),
            NSColor(deviceRed: 1, green: 1, blue: 0, alpha: 1),
        ])
        let mask = try maskPNG(values: [0, 255])

        let result = try SemanticMaskCompositor.composite(
            generatedData: generated,
            sourceData: source,
            maskData: mask
        )
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: result))
        let preserved = try XCTUnwrap(bitmap.colorAt(x: 0, y: 0))
        let replaced = try XCTUnwrap(bitmap.colorAt(x: 1, y: 0))

        XCTAssertGreaterThan(preserved.redComponent, 0.9)
        XCTAssertLessThan(preserved.greenComponent, 0.1)
        XCTAssertLessThan(preserved.blueComponent, 0.1)
        XCTAssertGreaterThan(replaced.redComponent, 0.9)
        XCTAssertGreaterThan(replaced.greenComponent, 0.8)
        XCTAssertLessThan(replaced.blueComponent, 0.1)
    }

    private func png(colors: [NSColor]) throws -> Data {
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: colors.count,
                pixelsHigh: 1,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: colors.count * 4,
                bitsPerPixel: 32
            )
        )
        for (x, color) in colors.enumerated() {
            bitmap.setColor(color, atX: x, y: 0)
        }
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    private func maskPNG(values: [UInt8]) throws -> Data {
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: values.count,
                pixelsHigh: 1,
                bitsPerSample: 8,
                samplesPerPixel: 1,
                hasAlpha: false,
                isPlanar: false,
                colorSpaceName: .deviceWhite,
                bytesPerRow: values.count,
                bitsPerPixel: 8
            )
        )
        guard let bytes = bitmap.bitmapData else {
            throw XCTSkip("无法访问测试蒙版像素")
        }
        for (index, value) in values.enumerated() {
            bytes[index] = value
        }
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}
