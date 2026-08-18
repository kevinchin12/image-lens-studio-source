import Foundation

/// Stable on-disk locations inside an Image Lens Studio workspace package.
///
/// Asset paths stored by `ImageLensCore.Workspace` are relative to `packageURL`.
/// This type centralizes the package contract so UI and provider layers do not
/// need to assemble filesystem paths independently.
public struct WorkspacePackageLayout: Equatable, Sendable {
    public static let manifestFileName = "manifest.json"
    public static let assetsDirectoryName = "assets"
    public static let originalAssetsDirectoryName = "original"
    public static let derivedAssetsDirectoryName = "derived"
    public static let thumbnailsDirectoryName = "thumbnails"
    public static let migrationBackupsDirectoryName = "migration-backups"

    public let packageURL: URL

    public init(packageURL: URL) {
        self.packageURL = packageURL.standardizedFileURL
    }

    public var manifestURL: URL {
        packageURL.appendingPathComponent(Self.manifestFileName, isDirectory: false)
    }

    public var assetsURL: URL {
        packageURL.appendingPathComponent(Self.assetsDirectoryName, isDirectory: true)
    }

    public var originalAssetsURL: URL {
        assetsURL.appendingPathComponent(Self.originalAssetsDirectoryName, isDirectory: true)
    }

    public var derivedAssetsURL: URL {
        assetsURL.appendingPathComponent(Self.derivedAssetsDirectoryName, isDirectory: true)
    }

    public var thumbnailsURL: URL {
        packageURL.appendingPathComponent(Self.thumbnailsDirectoryName, isDirectory: true)
    }

    public var migrationBackupsURL: URL {
        packageURL.appendingPathComponent(
            Self.migrationBackupsDirectoryName,
            isDirectory: true
        )
    }

    public func migrationBackupURL(forSchemaVersion version: Int) -> URL {
        migrationBackupsURL.appendingPathComponent(
            "manifest-v\(version).json",
            isDirectory: false
        )
    }

    public var requiredDirectoryURLs: [URL] {
        [assetsURL, originalAssetsURL, derivedAssetsURL, thumbnailsURL]
    }
}
