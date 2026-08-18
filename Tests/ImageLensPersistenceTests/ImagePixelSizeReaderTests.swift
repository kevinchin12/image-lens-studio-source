import AppKit
import Foundation
import ImageLensCore
import XCTest
@testable import ImageLensPersistence

final class ImagePixelSizeReaderTests: XCTestCase {
    func testReadsPixelDimensionsFromDataAndURL() throws {
        let data = try makePNGData(width: 7, height: 11)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ImagePixelSizeReaderTests-\(UUID().uuidString).png"
        )
        try data.write(to: url, options: [.atomic])
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(
            ImagePixelSizeReader.pixelSize(from: data),
            PixelSize(width: 7, height: 11)
        )
        XCTAssertEqual(
            ImagePixelSizeReader.pixelSize(at: url),
            PixelSize(width: 7, height: 11)
        )
    }

    func testInvalidImageMetadataReturnsNil() {
        XCTAssertNil(ImagePixelSizeReader.pixelSize(from: Data("not an image".utf8)))
    }

    private func makePNGData(width: Int, height: Int) throws -> Data {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        let data = representation.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }
}
