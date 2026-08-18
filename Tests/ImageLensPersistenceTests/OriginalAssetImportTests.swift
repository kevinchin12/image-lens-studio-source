import Foundation
import AppKit
import ImageLensCore
import XCTest
@testable import ImageLensPersistence

@MainActor
final class OriginalAssetImportTests: XCTestCase {
    func testImportCopiesOriginalAndReturnsManagedMetadata() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let sourceURL = fixture.sourceURL.appendingPathComponent("Reference Image.PNG")
        let sourceData = try makePNGData(width: 7, height: 11)
        try sourceData.write(to: sourceURL)

        let result = try await fixture.repository.importOriginalAsset(
            from: sourceURL,
            into: fixture.packageURL
        )

        XCTAssertEqual(result.fileName, "Reference Image.PNG")
        XCTAssertEqual(result.mimeType, "image/png")
        XCTAssertTrue(result.relativePath.hasPrefix("assets/original/sha256-"))
        XCTAssertTrue(result.relativePath.hasSuffix(".png"))
        XCTAssertEqual(result.pixelSize, PixelSize(width: 7, height: 11))
        XCTAssertTrue(result.contentHash?.hasPrefix("sha256:") == true)
        XCTAssertFalse(result.wasDeduplicated)
        XCTAssertEqual(
            try Data(contentsOf: fixture.packageURL.appendingPathComponent(result.relativePath)),
            sourceData
        )
    }

    func testRepeatedContentDeduplicatesAcrossSourceNames() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let data = Data("same image bytes".utf8)
        let firstURL = fixture.sourceURL.appendingPathComponent("first.png")
        let secondURL = fixture.sourceURL.appendingPathComponent("renamed.png")
        try data.write(to: firstURL)
        try data.write(to: secondURL)

        let first = try await fixture.repository.importOriginalAsset(
            from: firstURL,
            into: fixture.packageURL
        )
        let second = try await fixture.repository.importOriginalAsset(
            from: secondURL,
            into: fixture.packageURL
        )

        XCTAssertEqual(first.relativePath, second.relativePath)
        XCTAssertEqual(first.contentHash, second.contentHash)
        XCTAssertFalse(first.wasDeduplicated)
        XCTAssertTrue(second.wasDeduplicated)
        XCTAssertEqual(try originalAssetFileNames(in: fixture.packageURL).count, 1)
    }

    func testSupportedExtensionsReturnCanonicalMIMETypes() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let cases: [(extension: String, mimeType: String, storedExtension: String)] = [
            ("png", "image/png", "png"),
            ("jpg", "image/jpeg", "jpg"),
            ("jpeg", "image/jpeg", "jpg"),
            ("heic", "image/heic", "heic"),
            ("webp", "image/webp", "webp"),
            ("mov", "video/quicktime", "mov"),
            ("mp4", "video/mp4", "mp4"),
            ("m4v", "video/x-m4v", "m4v")
        ]

        for (index, item) in cases.enumerated() {
            let sourceURL = fixture.sourceURL.appendingPathComponent("fixture-\(index).\(item.extension)")
            try Data("fixture-\(index)".utf8).write(to: sourceURL)

            let result = try await fixture.repository.importOriginalAsset(
                from: sourceURL,
                into: fixture.packageURL
            )

            XCTAssertEqual(result.mimeType, item.mimeType)
            XCTAssertEqual(
                URL(fileURLWithPath: result.relativePath).pathExtension,
                item.storedExtension
            )
        }
    }

    func testUnsupportedExtensionIsRejectedWithoutCopying() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let sourceURL = fixture.sourceURL.appendingPathComponent("animation.gif")
        try Data("GIF89a".utf8).write(to: sourceURL)

        do {
            _ = try await fixture.repository.importOriginalAsset(
                from: sourceURL,
                into: fixture.packageURL
            )
            XCTFail("Expected unsupported extension error")
        } catch let error as WorkspacePackageRepositoryError {
            XCTAssertEqual(error, .unsupportedOriginalAssetExtension(sourceURL, extension: "gif"))
        }

        XCTAssertTrue(try originalAssetFileNames(in: fixture.packageURL).isEmpty)
    }

    func testDirectoryWithSupportedExtensionIsRejected() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let sourceURL = fixture.sourceURL.appendingPathComponent("folder.png", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: false)

        do {
            _ = try await fixture.repository.importOriginalAsset(
                from: sourceURL,
                into: fixture.packageURL
            )
            XCTFail("Expected regular-file validation error")
        } catch let error as WorkspacePackageRepositoryError {
            XCTAssertEqual(error, .originalAssetIsNotRegularFile(sourceURL))
        }
    }

    func testHashPathConflictNeverOverwritesExistingFile() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let sourceURL = fixture.sourceURL.appendingPathComponent("source.png")
        let sourceData = Data("original bytes".utf8)
        try sourceData.write(to: sourceURL)

        let first = try await fixture.repository.importOriginalAsset(
            from: sourceURL,
            into: fixture.packageURL
        )
        let firstDestination = fixture.packageURL.appendingPathComponent(first.relativePath)
        let conflictingData = Data("pre-existing conflict".utf8)
        try conflictingData.write(to: firstDestination)

        let second = try await fixture.repository.importOriginalAsset(
            from: sourceURL,
            into: fixture.packageURL
        )

        XCTAssertNotEqual(first.relativePath, second.relativePath)
        XCTAssertFalse(second.wasDeduplicated)
        XCTAssertEqual(try Data(contentsOf: firstDestination), conflictingData)
        XCTAssertEqual(
            try Data(contentsOf: fixture.packageURL.appendingPathComponent(second.relativePath)),
            sourceData
        )
    }

    private func makeFixture() async throws -> (
        rootURL: URL,
        sourceURL: URL,
        packageURL: URL,
        repository: WorkspacePackageRepository
    ) {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "OriginalAssetImportTests-\(UUID().uuidString)",
            isDirectory: true
        )
        let sourceURL = rootURL.appendingPathComponent("sources", isDirectory: true)
        let packageURL = rootURL.appendingPathComponent("Workspace.imagelens", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        let repository = WorkspacePackageRepository()
        try await repository.save(Workspace(title: "Import tests"), to: packageURL)
        return (rootURL, sourceURL, packageURL, repository)
    }

    private func originalAssetFileNames(in packageURL: URL) throws -> [String] {
        let directory = WorkspacePackageLayout(packageURL: packageURL).originalAssetsURL
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { !$0.hasPrefix(".importing-") }
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
