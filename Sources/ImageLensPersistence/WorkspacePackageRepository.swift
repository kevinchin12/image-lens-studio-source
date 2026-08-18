import Foundation
import ImageLensCore
#if canImport(CryptoKit)
import CryptoKit
#endif

public struct OriginalAssetImportResult: Equatable, Sendable {
    /// User-facing source filename. The managed on-disk filename is available as
    /// the last path component of `relativePath`.
    public var fileName: String
    public var relativePath: String
    public var mimeType: String
    public var pixelSize: PixelSize?
    public var contentHash: String?
    public var wasDeduplicated: Bool

    public init(
        fileName: String,
        relativePath: String,
        mimeType: String,
        pixelSize: PixelSize? = nil,
        contentHash: String?,
        wasDeduplicated: Bool
    ) {
        self.fileName = fileName
        self.relativePath = relativePath
        self.mimeType = mimeType
        self.pixelSize = pixelSize
        self.contentHash = contentHash
        self.wasDeduplicated = wasDeduplicated
    }
}

public struct DerivedAssetWriteResult: Equatable, Sendable {
    public var fileName: String
    public var relativePath: String
    public var mimeType: String
    public var contentHash: String?

    public init(fileName: String, relativePath: String, mimeType: String, contentHash: String?) {
        self.fileName = fileName
        self.relativePath = relativePath
        self.mimeType = mimeType
        self.contentHash = contentHash
    }
}

/// A content-addressed mask stored with the workspace's derived assets.
///
/// The relative path is safe to persist in the workspace manifest. Callers
/// should use `readMaskArtifact(relativePath:from:)` to load the bytes again so
/// the derived-only path boundary is enforced on reads as well as writes.
public struct MaskArtifactWriteResult: Equatable, Sendable {
    public var relativePath: String
    public var contentHash: String?

    public init(relativePath: String, contentHash: String?) {
        self.relativePath = relativePath
        self.contentHash = contentHash
    }
}

public struct WorkspaceStorageUsage: Equatable, Sendable {
    public var totalBytes: Int64
    public var originalAssetBytes: Int64
    public var derivedAssetBytes: Int64
    public var thumbnailBytes: Int64
    public var otherBytes: Int64

    public init(
        totalBytes: Int64,
        originalAssetBytes: Int64,
        derivedAssetBytes: Int64,
        thumbnailBytes: Int64,
        otherBytes: Int64
    ) {
        self.totalBytes = totalBytes
        self.originalAssetBytes = originalAssetBytes
        self.derivedAssetBytes = derivedAssetBytes
        self.thumbnailBytes = thumbnailBytes
        self.otherBytes = otherBytes
    }
}

public struct WorkspaceStorageCleanupPlan: Equatable, Sendable {
    public var usage: WorkspaceStorageUsage
    public var removableAssetIDs: [AssetID]
    public var removableRelativePaths: [String]
    public var orphanRelativePaths: [String]
    public var reclaimableBytes: Int64

    public init(
        usage: WorkspaceStorageUsage,
        removableAssetIDs: [AssetID],
        removableRelativePaths: [String],
        orphanRelativePaths: [String],
        reclaimableBytes: Int64
    ) {
        self.usage = usage
        self.removableAssetIDs = removableAssetIDs
        self.removableRelativePaths = removableRelativePaths
        self.orphanRelativePaths = orphanRelativePaths
        self.reclaimableBytes = reclaimableBytes
    }

    public var removableFileCount: Int {
        Set(removableRelativePaths + orphanRelativePaths).count
    }
}

public enum WorkspacePackageRepositoryError: Error, Equatable, Sendable {
    case packageNotFound(URL)
    case packageIsNotDirectory(URL)
    case manifestMissing(URL)
    case unreadableManifest(URL, reason: String)
    case corruptManifest(URL, reason: String)
    case unsupportedSchemaVersion(found: Int, supported: Int)
    case migrationFailed(from: Int, to: Int, reason: String)
    case migrationRecoveryAvailable(manifest: URL, backup: URL, reason: String)
    case writeFailed(URL, reason: String)
    case packageAlreadyExists(URL)
    case originalAssetIsNotRegularFile(URL)
    case unsupportedOriginalAssetExtension(URL, extension: String)
    case originalAssetImportFailed(URL, reason: String)
    case managedAssetUnavailable(URL, reason: String)
}

extension WorkspacePackageRepositoryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .packageNotFound(let url):
            "Workspace package was not found at \(url.path)."
        case .packageIsNotDirectory(let url):
            "Workspace package is not a directory at \(url.path)."
        case .manifestMissing(let url):
            "Workspace manifest is missing at \(url.path)."
        case .unreadableManifest(let url, let reason):
            "Workspace manifest at \(url.path) could not be read: \(reason)"
        case .corruptManifest(let url, let reason):
            "Workspace manifest at \(url.path) is corrupt: \(reason)"
        case .unsupportedSchemaVersion(let found, let supported):
            "Workspace schema version \(found) is unsupported; this build supports version \(supported)."
        case .migrationFailed(let source, let destination, let reason):
            "Workspace migration from schema \(source) to \(destination) failed: \(reason)"
        case .migrationRecoveryAvailable(let manifest, let backup, let reason):
            "Workspace manifest at \(manifest.path) is invalid. Its original pre-migration manifest is available at \(backup.path); restoring it may discard edits made after migration: \(reason)"
        case .writeFailed(let url, let reason):
            "Workspace package at \(url.path) could not be saved: \(reason)"
        case .packageAlreadyExists(let url):
            "A workspace package already exists at \(url.path)."
        case .originalAssetIsNotRegularFile(let url):
            "Original asset at \(url.path) is not a regular file."
        case .unsupportedOriginalAssetExtension(let url, let fileExtension):
            "Original asset at \(url.path) uses unsupported extension '\(fileExtension)'."
        case .originalAssetImportFailed(let url, let reason):
            "Original asset at \(url.path) could not be imported: \(reason)"
        case .managedAssetUnavailable(let url, let reason):
            "Managed asset at \(url.path) is unavailable: \(reason)"
        }
    }
}

/// Actor-isolated repository for a versioned workspace directory package.
///
/// Ordinary saves update only the manifest atomically. Assets already live in
/// managed package directories and must not be recopied for every canvas edit.
/// Full package copying is reserved for explicit clone / Save As operations.
public actor WorkspacePackageRepository {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func load(from packageURL: URL) async throws -> Workspace {
        let layout = WorkspacePackageLayout(packageURL: packageURL)
        try validatePackageDirectory(at: layout.packageURL)

        guard fileManager.fileExists(atPath: layout.manifestURL.path) else {
            throw WorkspacePackageRepositoryError.manifestMissing(layout.manifestURL)
        }

        let data: Data
        do {
            data = try Data(contentsOf: layout.manifestURL, options: [.mappedIfSafe])
        } catch {
            throw WorkspacePackageRepositoryError.unreadableManifest(
                layout.manifestURL,
                reason: error.localizedDescription
            )
        }

        let decoder = JSONDecoder()
        let version: ManifestVersion
        do {
            version = try decoder.decode(ManifestVersion.self, from: data)
        } catch {
            if let backupURL = availableMigrationBackup(in: layout) {
                throw WorkspacePackageRepositoryError.migrationRecoveryAvailable(
                    manifest: layout.manifestURL,
                    backup: backupURL,
                    reason: Self.decodingReason(for: error)
                )
            }
            throw WorkspacePackageRepositoryError.corruptManifest(
                layout.manifestURL,
                reason: Self.decodingReason(for: error)
            )
        }

        guard version.schemaVersion >= WorkspaceManifestMigrator.oldestSupportedSchemaVersion,
              version.schemaVersion <= Workspace.currentSchemaVersion else {
            throw WorkspacePackageRepositoryError.unsupportedSchemaVersion(
                found: version.schemaVersion,
                supported: Workspace.currentSchemaVersion
            )
        }

        if version.schemaVersion < Workspace.currentSchemaVersion {
            let migration: WorkspaceMigrationResult
            do {
                migration = try WorkspaceManifestMigrator.migrate(
                    data: data,
                    sourceVersion: version.schemaVersion,
                    decoder: decoder
                )
            } catch {
                throw WorkspacePackageRepositoryError.migrationFailed(
                    from: version.schemaVersion,
                    to: Workspace.currentSchemaVersion,
                    reason: Self.decodingReason(for: error)
                )
            }
            _ = try installMigratedManifest(
                migration.workspace,
                originalData: data,
                sourceVersion: version.schemaVersion,
                layout: layout
            )
            return migration.workspace
        }

        do {
            return try decoder.decode(Workspace.self, from: data)
        } catch {
            if let backupURL = availableMigrationBackup(in: layout) {
                throw WorkspacePackageRepositoryError.migrationRecoveryAvailable(
                    manifest: layout.manifestURL,
                    backup: backupURL,
                    reason: Self.decodingReason(for: error)
                )
            }
            throw WorkspacePackageRepositoryError.corruptManifest(
                layout.manifestURL,
                reason: Self.decodingReason(for: error)
            )
        }
    }

    public func save(_ workspace: Workspace, to packageURL: URL) async throws {
        guard workspace.schemaVersion == Workspace.currentSchemaVersion else {
            throw WorkspacePackageRepositoryError.unsupportedSchemaVersion(
                found: workspace.schemaVersion,
                supported: Workspace.currentSchemaVersion
            )
        }

        let destination = WorkspacePackageLayout(packageURL: packageURL)
        do {
            let parentURL = destination.packageURL.deletingLastPathComponent()
            try fileManager.createDirectory(
                at: parentURL,
                withIntermediateDirectories: true
            )

            var destinationIsDirectory: ObjCBool = false
            let destinationExists = fileManager.fileExists(
                atPath: destination.packageURL.path,
                isDirectory: &destinationIsDirectory
            )
            if destinationExists && !destinationIsDirectory.boolValue {
                throw WorkspacePackageRepositoryError.packageIsNotDirectory(destination.packageURL)
            }

            if !destinationExists {
                try fileManager.createDirectory(
                    at: destination.packageURL,
                    withIntermediateDirectories: false
                )
            }

            for directoryURL in destination.requiredDirectoryURLs {
                try fileManager.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true
                )
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let manifestData = try encoder.encode(workspace)
            try manifestData.write(to: destination.manifestURL, options: [.atomic])
        } catch let error as WorkspacePackageRepositoryError {
            throw error
        } catch {
            throw WorkspacePackageRepositoryError.writeFailed(
                destination.packageURL,
                reason: error.localizedDescription
            )
        }
    }

    /// Installs a new empty project package. If the destination already exists,
    /// it is replaced as a whole; no assets from the previous project leak into
    /// the newly created one after the save panel's Replace confirmation.
    public func createPackage(_ workspace: Workspace, at packageURL: URL) async throws {
        guard workspace.schemaVersion == Workspace.currentSchemaVersion else {
            throw WorkspacePackageRepositoryError.unsupportedSchemaVersion(
                found: workspace.schemaVersion,
                supported: Workspace.currentSchemaVersion
            )
        }

        let destination = WorkspacePackageLayout(packageURL: packageURL)
        let parentURL = destination.packageURL.deletingLastPathComponent()
        let stagingURL = parentURL.appendingPathComponent(
            ".\(destination.packageURL.lastPathComponent).staging-\(UUID().uuidString)",
            isDirectory: true
        )
        let staging = WorkspacePackageLayout(packageURL: stagingURL)

        do {
            try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: staging.packageURL, withIntermediateDirectories: false)
            for directoryURL in staging.requiredDirectoryURLs {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(workspace).write(to: staging.manifestURL, options: [.atomic])

            if fileManager.fileExists(atPath: destination.packageURL.path) {
                _ = try fileManager.replaceItemAt(
                    destination.packageURL,
                    withItemAt: staging.packageURL,
                    backupItemName: nil,
                    options: [.usingNewMetadataOnly]
                )
            } else {
                try fileManager.moveItem(at: staging.packageURL, to: destination.packageURL)
            }
        } catch {
            try? removeStagingPackageIfPresent(at: staging.packageURL)
            throw WorkspacePackageRepositoryError.writeFailed(
                destination.packageURL,
                reason: error.localizedDescription
            )
        }
    }

    /// Creates a complete independent project from an existing package.
    /// `workspace` is written as the destination manifest after all package
    /// contents have been copied, so callers can assign a fresh project ID for
    /// Save As while preserving all internal asset references.
    public func clonePackage(
        from sourceURL: URL,
        to destinationURL: URL,
        workspace: Workspace
    ) async throws {
        guard workspace.schemaVersion == Workspace.currentSchemaVersion else {
            throw WorkspacePackageRepositoryError.unsupportedSchemaVersion(
                found: workspace.schemaVersion,
                supported: Workspace.currentSchemaVersion
            )
        }

        let source = WorkspacePackageLayout(packageURL: sourceURL)
        let destination = WorkspacePackageLayout(packageURL: destinationURL)
        try validatePackageDirectory(at: source.packageURL)

        var destinationIsDirectory: ObjCBool = false
        let destinationExists = fileManager.fileExists(
            atPath: destination.packageURL.path,
            isDirectory: &destinationIsDirectory
        )
        if destinationExists && !destinationIsDirectory.boolValue {
            throw WorkspacePackageRepositoryError.packageIsNotDirectory(destination.packageURL)
        }

        let parentURL = destination.packageURL.deletingLastPathComponent()
        let stagingURL = parentURL.appendingPathComponent(
            ".\(destination.packageURL.lastPathComponent).staging-\(UUID().uuidString)",
            isDirectory: true
        )
        let staging = WorkspacePackageLayout(packageURL: stagingURL)

        do {
            try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
            try fileManager.copyItem(at: source.packageURL, to: staging.packageURL)
            for directoryURL in staging.requiredDirectoryURLs {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(workspace).write(to: staging.manifestURL, options: [.atomic])
            if destinationExists {
                _ = try fileManager.replaceItemAt(
                    destination.packageURL,
                    withItemAt: staging.packageURL,
                    backupItemName: nil,
                    options: [.usingNewMetadataOnly]
                )
            } else {
                try fileManager.moveItem(at: staging.packageURL, to: destination.packageURL)
            }
        } catch let error as WorkspacePackageRepositoryError {
            try? removeStagingPackageIfPresent(at: staging.packageURL)
            throw error
        } catch {
            try? removeStagingPackageIfPresent(at: staging.packageURL)
            throw WorkspacePackageRepositoryError.writeFailed(
                destination.packageURL,
                reason: error.localizedDescription
            )
        }
    }

    public func removePackage(at packageURL: URL) async throws {
        let layout = WorkspacePackageLayout(packageURL: packageURL)
        try validatePackageDirectory(at: layout.packageURL)
        do {
            try fileManager.removeItem(at: layout.packageURL)
        } catch {
            throw WorkspacePackageRepositoryError.writeFailed(
                layout.packageURL,
                reason: error.localizedDescription
            )
        }
    }

    /// Copies a user-selected image or video into the managed `assets/original` directory.
    ///
    /// The repository owns all filesystem work. A SHA-256 content address is used
    /// when CryptoKit is available, making repeated imports stable and deduplicated.
    /// A sibling staging file is moved into place so a failed copy never leaves a
    /// partially written file at the final relative path.
    public func importOriginalAsset(
        from sourceURL: URL,
        into packageURL: URL
    ) async throws -> OriginalAssetImportResult {
        let source = sourceURL.standardizedFileURL
        let layout = WorkspacePackageLayout(packageURL: packageURL)
        try validatePackageDirectory(at: layout.packageURL)

        let didAccessSecurityScopedResource = source.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScopedResource {
                source.stopAccessingSecurityScopedResource()
            }
        }

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: source.path)
        } catch {
            throw WorkspacePackageRepositoryError.originalAssetImportFailed(
                source,
                reason: error.localizedDescription
            )
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw WorkspacePackageRepositoryError.originalAssetIsNotRegularFile(source)
        }

        let fileExtension = source.pathExtension.lowercased()
        guard let mediaType = Self.supportedOriginalAssetTypes[fileExtension] else {
            throw WorkspacePackageRepositoryError.unsupportedOriginalAssetExtension(
                source,
                extension: fileExtension
            )
        }

        do {
            try fileManager.createDirectory(
                at: layout.originalAssetsURL,
                withIntermediateDirectories: true
            )

            let contentHash = try sha256ContentHash(for: source)
            let baseName = contentHash.map(Self.fileSystemHashComponent(from:))
                ?? Self.sanitizedStem(from: source)
            let destination = try destinationForImport(
                in: layout.originalAssetsURL,
                baseName: baseName,
                canonicalExtension: mediaType.canonicalExtension,
                expectedContentHash: contentHash
            )

            if destination.wasDeduplicated {
                return Self.importResult(
                    source: source,
                    destinationURL: destination.url,
                    mediaType: mediaType,
                    contentHash: contentHash,
                    wasDeduplicated: true
                )
            }

            let stagingURL = layout.originalAssetsURL.appendingPathComponent(
                ".importing-\(UUID().uuidString)",
                isDirectory: false
            )
            do {
                try fileManager.copyItem(at: source, to: stagingURL)
                if let contentHash,
                   try sha256ContentHash(for: stagingURL) != contentHash {
                    throw WorkspacePackageRepositoryError.originalAssetImportFailed(
                        source,
                        reason: "The source changed while it was being imported."
                    )
                }
                try fileManager.moveItem(at: stagingURL, to: destination.url)
            } catch {
                try? removeItemIfPresent(at: stagingURL)
                throw error
            }

            return Self.importResult(
                source: source,
                destinationURL: destination.url,
                mediaType: mediaType,
                contentHash: contentHash,
                wasDeduplicated: false
            )
        } catch let error as WorkspacePackageRepositoryError {
            throw error
        } catch {
            throw WorkspacePackageRepositoryError.originalAssetImportFailed(
                source,
                reason: error.localizedDescription
            )
        }
    }

    public func readAssetData(relativePath: String, from packageURL: URL) async throws -> Data {
        let assetURL = try managedAssetURL(
            relativePath: relativePath,
            packageURL: packageURL
        )
        do {
            return try Data(contentsOf: assetURL, options: [.mappedIfSafe])
        } catch {
            throw WorkspacePackageRepositoryError.originalAssetImportFailed(
                assetURL,
                reason: error.localizedDescription
            )
        }
    }

    /// Copies a managed project asset to a user-selected destination without
    /// loading the complete image or video into memory.
    public func exportManagedAsset(
        relativePath: String,
        from packageURL: URL,
        to destinationURL: URL,
        overwrite: Bool = false
    ) async throws {
        let sourceURL = try resolveManagedAssetURL(
            relativePath: relativePath,
            from: packageURL
        )
        let destination = destinationURL.standardizedFileURL
        let resolvedPackage = packageURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedDestination = destination.resolvingSymlinksInPath().standardizedFileURL
        let packagePath = resolvedPackage.path.hasSuffix("/")
            ? resolvedPackage.path
            : resolvedPackage.path + "/"

        guard sourceURL != resolvedDestination else {
            throw WorkspacePackageRepositoryError.writeFailed(
                destination,
                reason: "The export destination is the managed source file."
            )
        }
        guard !resolvedDestination.path.hasPrefix(packagePath) else {
            throw WorkspacePackageRepositoryError.writeFailed(
                destination,
                reason: "Generated results cannot be exported inside the project package."
            )
        }
        if fileManager.fileExists(atPath: destination.path), !overwrite {
            throw WorkspacePackageRepositoryError.writeFailed(
                destination,
                reason: "A file already exists at the export destination."
            )
        }

        let didAccessSecurityScopedResource = destination.startAccessingSecurityScopedResource()
        defer {
            if didAccessSecurityScopedResource {
                destination.stopAccessingSecurityScopedResource()
            }
        }

        let parentURL = destination.deletingLastPathComponent()
        let stagingURL = parentURL.appendingPathComponent(
            ".exporting-\(UUID().uuidString)-\(destination.lastPathComponent)",
            isDirectory: false
        )
        do {
            try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
            try fileManager.copyItem(at: sourceURL, to: stagingURL)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(
                    destination,
                    withItemAt: stagingURL,
                    backupItemName: nil,
                    options: [.usingNewMetadataOnly]
                )
            } else {
                try fileManager.moveItem(at: stagingURL, to: destination)
            }
        } catch {
            try? removeItemIfPresent(at: stagingURL)
            throw WorkspacePackageRepositoryError.writeFailed(
                destination,
                reason: error.localizedDescription
            )
        }
    }

    public func storageCleanupPlan(
        for workspace: Workspace,
        at packageURL: URL
    ) async throws -> WorkspaceStorageCleanupPlan {
        let layout = WorkspacePackageLayout(packageURL: packageURL)
        try validatePackageDirectory(at: layout.packageURL)

        let candidateAssetIDs = WorkspaceStorageCleanupPolicy
            .removableGeneratedAssetIDs(in: workspace)
        let candidateIDSet = Set(candidateAssetIDs)
        let retainedAssets = workspace.assets.filter { !candidateIDSet.contains($0.id) }
        let retainedPaths = Set(
            retainedAssets.flatMap { asset in
                [asset.relativePath, asset.thumbnailRelativePath].compactMap { $0 }
            }
        )
        let migrationProtectedPaths = migrationBackupAssetPaths(in: layout)
        let candidatePaths = Set(
            workspace.assets
                .filter { candidateIDSet.contains($0.id) }
                .flatMap { asset in
                    [asset.relativePath, asset.thumbnailRelativePath].compactMap { $0 }
                }
                .filter { path in
                    !retainedPaths.contains(path) && Self.isCleanupManagedPath(path)
                }
        ).subtracting(migrationProtectedPaths)
        let removableAssetIDs = workspace.assets.compactMap { asset -> AssetID? in
            guard candidateIDSet.contains(asset.id),
                  candidatePaths.contains(asset.relativePath) else { return nil }
            return asset.id
        }
        let removableIDSet = Set(removableAssetIDs)
        let removablePaths = Set(
            workspace.assets
                .filter { removableIDSet.contains($0.id) }
                .flatMap { asset in
                    [asset.relativePath, asset.thumbnailRelativePath].compactMap { $0 }
                }
                .filter { path in
                    !retainedPaths.contains(path)
                        && !migrationProtectedPaths.contains(path)
                        && Self.isCleanupManagedPath(path)
                }
        )

        let derivedFiles = try regularFiles(in: layout.derivedAssetsURL, relativeTo: layout.packageURL)
        let thumbnailFiles = try regularFiles(in: layout.thumbnailsURL, relativeTo: layout.packageURL)
        let manifestPaths = Set(
            workspace.assets.flatMap { asset in
                [asset.relativePath, asset.thumbnailRelativePath].compactMap { $0 }
            }
        )
        .union(workspace.generators.compactMap { $0.imageEdit?.maskRelativePath })
        .union(workspace.generations.compactMap { $0.imageEditSnapshot?.maskRelativePath })
        let orphanPaths = Set(derivedFiles.keys)
            .union(thumbnailFiles.keys)
            .subtracting(manifestPaths)
            .subtracting(migrationProtectedPaths)

        let originalFiles = try regularFiles(in: layout.originalAssetsURL, relativeTo: layout.packageURL)
        let allPackageFiles = try regularFiles(in: layout.packageURL, relativeTo: layout.packageURL)
        let originalBytes = originalFiles.values.reduce(0, +)
        let derivedBytes = derivedFiles.values.reduce(0, +)
        let thumbnailBytes = thumbnailFiles.values.reduce(0, +)
        let totalBytes = allPackageFiles.values.reduce(0, +)
        let knownBytes = originalBytes + derivedBytes + thumbnailBytes
        let reclaimablePaths = removablePaths.union(orphanPaths)
        let reclaimableBytes = reclaimablePaths.reduce(Int64(0)) { partial, path in
            partial + (allPackageFiles[path] ?? 0)
        }

        return WorkspaceStorageCleanupPlan(
            usage: WorkspaceStorageUsage(
                totalBytes: totalBytes,
                originalAssetBytes: originalBytes,
                derivedAssetBytes: derivedBytes,
                thumbnailBytes: thumbnailBytes,
                otherBytes: max(0, totalBytes - knownBytes)
            ),
            removableAssetIDs: removableAssetIDs,
            removableRelativePaths: removablePaths.sorted(),
            orphanRelativePaths: orphanPaths.sorted(),
            reclaimableBytes: reclaimableBytes
        )
    }

    /// Removes only explicitly planned files from managed derived/thumbnails
    /// directories. Missing files are harmless, making cleanup resumable.
    public func removeCleanupFiles(
        relativePaths: [String],
        from packageURL: URL
    ) async throws {
        for relativePath in Set(relativePaths) {
            guard Self.isCleanupManagedPath(relativePath) else {
                throw WorkspacePackageRepositoryError.writeFailed(
                    packageURL,
                    reason: "Refusing to clean a non-derived project path: \(relativePath)"
                )
            }
            let candidate = try managedAssetURL(
                relativePath: relativePath,
                packageURL: packageURL
            )
            guard fileManager.fileExists(atPath: candidate.path) else { continue }
            let resolvedPackage = packageURL.resolvingSymlinksInPath().standardizedFileURL
            let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
            let packagePath = resolvedPackage.path.hasSuffix("/")
                ? resolvedPackage.path
                : resolvedPackage.path + "/"
            guard resolvedCandidate.path.hasPrefix(packagePath) else {
                throw WorkspacePackageRepositoryError.managedAssetUnavailable(
                    candidate,
                    reason: "Cleanup path escapes the workspace package."
                )
            }
            do {
                try fileManager.removeItem(at: candidate)
            } catch {
                throw WorkspacePackageRepositoryError.writeFailed(
                    candidate,
                    reason: error.localizedDescription
                )
            }
        }
    }

    /// Resolves a persisted relative asset path to a regular file contained
    /// by the workspace package, including after symbolic-link resolution.
    public func resolveManagedAssetURL(
        relativePath: String,
        from packageURL: URL
    ) throws -> URL {
        let candidate = try managedAssetURL(
            relativePath: relativePath,
            packageURL: packageURL
        )
        let resolvedPackage = packageURL.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        let packagePath = resolvedPackage.path.hasSuffix("/")
            ? resolvedPackage.path
            : resolvedPackage.path + "/"
        guard resolvedCandidate.path.hasPrefix(packagePath) else {
            throw WorkspacePackageRepositoryError.managedAssetUnavailable(
                candidate,
                reason: "Asset path escapes the workspace package."
            )
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolvedCandidate.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw WorkspacePackageRepositoryError.managedAssetUnavailable(
                resolvedCandidate,
                reason: "Asset is missing or is not a regular file."
            )
        }
        let values = try resolvedCandidate.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            throw WorkspacePackageRepositoryError.managedAssetUnavailable(
                resolvedCandidate,
                reason: "Asset is not a regular file."
            )
        }
        return resolvedCandidate
    }

    public func readAssetPixelSize(
        relativePath: String,
        from packageURL: URL
    ) async throws -> PixelSize? {
        let assetURL = try managedAssetURL(
            relativePath: relativePath,
            packageURL: packageURL
        )
        return ImagePixelSizeReader.pixelSize(at: assetURL)
    }

    public func importOriginalAssetData(
        _ data: Data,
        mimeType: String,
        suggestedName: String,
        into packageURL: URL
    ) async throws -> OriginalAssetImportResult {
        let layout = WorkspacePackageLayout(packageURL: packageURL)
        try validatePackageDirectory(at: layout.packageURL)
        guard !data.isEmpty else {
            throw WorkspacePackageRepositoryError.originalAssetImportFailed(
                layout.originalAssetsURL,
                reason: "Clipboard image is empty."
            )
        }
        guard mimeType.lowercased().hasPrefix("image/") else {
            throw WorkspacePackageRepositoryError.originalAssetImportFailed(
                layout.originalAssetsURL,
                reason: "Clipboard data import only accepts image content."
            )
        }
        let mediaType: OriginalAssetMediaType
        switch mimeType.lowercased() {
        case "image/jpeg", "image/jpg":
            mediaType = OriginalAssetMediaType(mimeType: "image/jpeg", canonicalExtension: "jpg")
        case "image/webp":
            mediaType = OriginalAssetMediaType(mimeType: "image/webp", canonicalExtension: "webp")
        default:
            mediaType = OriginalAssetMediaType(mimeType: "image/png", canonicalExtension: "png")
        }

        do {
            try fileManager.createDirectory(at: layout.originalAssetsURL, withIntermediateDirectories: true)
            let contentHash = sha256ContentHash(for: data)
            let baseName = contentHash.map(Self.fileSystemHashComponent(from:)) ?? "clipboard"
            let destination = try destinationForImport(
                in: layout.originalAssetsURL,
                baseName: baseName,
                canonicalExtension: mediaType.canonicalExtension,
                expectedContentHash: contentHash
            )
            if !destination.wasDeduplicated {
                try data.write(to: destination.url, options: [.atomic])
            }
            return OriginalAssetImportResult(
                fileName: suggestedName,
                relativePath: [
                    WorkspacePackageLayout.assetsDirectoryName,
                    WorkspacePackageLayout.originalAssetsDirectoryName,
                    destination.url.lastPathComponent
                ].joined(separator: "/"),
                mimeType: mediaType.mimeType,
                pixelSize: ImagePixelSizeReader.pixelSize(from: data),
                contentHash: contentHash,
                wasDeduplicated: destination.wasDeduplicated
            )
        } catch let error as WorkspacePackageRepositoryError {
            throw error
        } catch {
            throw WorkspacePackageRepositoryError.originalAssetImportFailed(
                layout.originalAssetsURL,
                reason: error.localizedDescription
            )
        }
    }

    public func writeDerivedAsset(
        _ data: Data,
        mimeType: String,
        generationID: GenerationID,
        index: Int,
        into packageURL: URL
    ) async throws -> DerivedAssetWriteResult {
        let layout = WorkspacePackageLayout(packageURL: packageURL)
        try validatePackageDirectory(at: layout.packageURL)
        guard !data.isEmpty else {
            throw WorkspacePackageRepositoryError.writeFailed(
                layout.derivedAssetsURL,
                reason: "Generated media is empty."
            )
        }
        let fileExtension: String
        switch mimeType.lowercased() {
        case "image/jpeg", "image/jpg": fileExtension = "jpg"
        case "image/webp": fileExtension = "webp"
        case "image/heic", "image/heif": fileExtension = "heic"
        case "image/png": fileExtension = "png"
        case "video/mp4": fileExtension = "mp4"
        case "video/quicktime": fileExtension = "mov"
        case "video/x-m4v": fileExtension = "m4v"
        default:
            throw WorkspacePackageRepositoryError.writeFailed(
                layout.derivedAssetsURL,
                reason: "Unsupported generated media MIME type: \(mimeType)"
            )
        }
        do {
            try fileManager.createDirectory(at: layout.derivedAssetsURL, withIntermediateDirectories: true)
            let fileName = "generation-\(generationID.rawValue.uuidString.lowercased())-\(index + 1).\(fileExtension)"
            let destination = layout.derivedAssetsURL.appendingPathComponent(fileName)
            try data.write(to: destination, options: [.atomic])
            let hash = try sha256ContentHash(for: destination)
            return DerivedAssetWriteResult(
                fileName: fileName,
                relativePath: [
                    WorkspacePackageLayout.assetsDirectoryName,
                    WorkspacePackageLayout.derivedAssetsDirectoryName,
                    fileName
                ].joined(separator: "/"),
                mimeType: mimeType,
                contentHash: hash
            )
        } catch let error as WorkspacePackageRepositoryError {
            throw error
        } catch {
            throw WorkspacePackageRepositoryError.writeFailed(
                layout.derivedAssetsURL,
                reason: error.localizedDescription
            )
        }
    }

    /// Atomically stores a PNG mask in `assets/derived`.
    ///
    /// Generator and source identifiers are included in the filename so a
    /// package remains diagnosable without consulting its manifest. The
    /// content hash makes repeated writes of the same mask idempotent.
    public func writeMaskArtifact(
        _ pngData: Data,
        generatorID: GeneratorID,
        sourceAssetID: AssetID,
        into packageURL: URL
    ) async throws -> MaskArtifactWriteResult {
        let layout = WorkspacePackageLayout(packageURL: packageURL)
        try validatePackageDirectory(at: layout.packageURL)
        guard pngData.starts(with: Self.pngSignature) else {
            throw WorkspacePackageRepositoryError.writeFailed(
                layout.derivedAssetsURL,
                reason: "Mask artifact must contain non-empty PNG data."
            )
        }

        do {
            try fileManager.createDirectory(
                at: layout.derivedAssetsURL,
                withIntermediateDirectories: true
            )
            let contentHash = sha256ContentHash(for: pngData)
            let hashComponent = contentHash.map(Self.fileSystemHashComponent(from:))
                ?? UUID().uuidString.lowercased()
            let baseName = [
                "mask",
                generatorID.rawValue.uuidString.lowercased(),
                sourceAssetID.rawValue.uuidString.lowercased(),
                hashComponent
            ].joined(separator: "-")
            let destination = try destinationForImport(
                in: layout.derivedAssetsURL,
                baseName: baseName,
                canonicalExtension: "png",
                expectedContentHash: contentHash
            )
            if !destination.wasDeduplicated {
                try pngData.write(to: destination.url, options: [.atomic])
            }
            return MaskArtifactWriteResult(
                relativePath: [
                    WorkspacePackageLayout.assetsDirectoryName,
                    WorkspacePackageLayout.derivedAssetsDirectoryName,
                    destination.url.lastPathComponent
                ].joined(separator: "/"),
                contentHash: contentHash
            )
        } catch let error as WorkspacePackageRepositoryError {
            throw error
        } catch {
            throw WorkspacePackageRepositoryError.writeFailed(
                layout.derivedAssetsURL,
                reason: error.localizedDescription
            )
        }
    }

    /// Reads a mask only when its persisted path resolves to a regular file in
    /// `assets/derived`. Original assets, traversal paths, directories and
    /// escaping symbolic links are rejected.
    public func readMaskArtifact(
        relativePath: String,
        from packageURL: URL
    ) async throws -> Data {
        guard Self.isMaskArtifactPath(relativePath) else {
            throw WorkspacePackageRepositoryError.managedAssetUnavailable(
                packageURL.appendingPathComponent(relativePath),
                reason: "Mask artifacts must be PNG files stored directly in assets/derived."
            )
        }
        let artifactURL = try resolveManagedAssetURL(
            relativePath: relativePath,
            from: packageURL
        )
        let derivedDirectory = WorkspacePackageLayout(packageURL: packageURL)
            .derivedAssetsURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let derivedPath = derivedDirectory.path.hasSuffix("/")
            ? derivedDirectory.path
            : derivedDirectory.path + "/"
        guard artifactURL.path.hasPrefix(derivedPath) else {
            throw WorkspacePackageRepositoryError.managedAssetUnavailable(
                artifactURL,
                reason: "Mask artifact path escapes assets/derived."
            )
        }
        do {
            let data = try Data(contentsOf: artifactURL, options: [.mappedIfSafe])
            guard data.starts(with: Self.pngSignature) else {
                throw WorkspacePackageRepositoryError.managedAssetUnavailable(
                    artifactURL,
                    reason: "Mask artifact does not contain PNG data."
                )
            }
            return data
        } catch let error as WorkspacePackageRepositoryError {
            throw error
        } catch {
            throw WorkspacePackageRepositoryError.managedAssetUnavailable(
                artifactURL,
                reason: error.localizedDescription
            )
        }
    }

    @discardableResult
    private func installMigratedManifest(
        _ workspace: Workspace,
        originalData: Data,
        sourceVersion: Int,
        layout: WorkspacePackageLayout
    ) throws -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        let migratedData: Data
        do {
            migratedData = try encoder.encode(workspace)
            let verified = try JSONDecoder().decode(Workspace.self, from: migratedData)
            guard verified.schemaVersion == Workspace.currentSchemaVersion else {
                throw WorkspaceManifestMigrationError.missingMigrationStep(
                    verified.schemaVersion
                )
            }
        } catch {
            throw WorkspacePackageRepositoryError.migrationFailed(
                from: sourceVersion,
                to: Workspace.currentSchemaVersion,
                reason: Self.decodingReason(for: error)
            )
        }

        let backupURL = layout.migrationBackupURL(forSchemaVersion: sourceVersion)
        do {
            try fileManager.createDirectory(
                at: layout.migrationBackupsURL,
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: backupURL.path) {
                let existingBackup = try Data(
                    contentsOf: backupURL,
                    options: [.mappedIfSafe]
                )
                guard existingBackup == originalData else {
                    throw WorkspaceManifestMigrationError.preservationCheckFailed(
                        "existing migration backup does not match the current source manifest"
                    )
                }
            } else {
                try originalData.write(to: backupURL, options: [.atomic])
            }

            try migratedData.write(to: layout.manifestURL, options: [.atomic])
            let installedData = try Data(
                contentsOf: layout.manifestURL,
                options: [.mappedIfSafe]
            )
            let installedWorkspace = try JSONDecoder().decode(
                Workspace.self,
                from: installedData
            )
            guard installedWorkspace.schemaVersion == Workspace.currentSchemaVersion else {
                throw WorkspaceManifestMigrationError.missingMigrationStep(
                    installedWorkspace.schemaVersion
                )
            }
            return true
        } catch {
            let installationReason = Self.decodingReason(for: error)
            do {
                try originalData.write(to: layout.manifestURL, options: [.atomic])
                // The project can still open with the in-memory migrated model.
                // A later Save As can persist it somewhere writable.
                return false
            } catch {
                if let backupURL = availableMigrationBackup(in: layout) {
                    throw WorkspacePackageRepositoryError.migrationRecoveryAvailable(
                        manifest: layout.manifestURL,
                        backup: backupURL,
                        reason: "Migration installation failed (\(installationReason)); restoring the original manifest also failed (\(error.localizedDescription))."
                    )
                }
                throw WorkspacePackageRepositoryError.migrationFailed(
                    from: sourceVersion,
                    to: Workspace.currentSchemaVersion,
                    reason: "Migration installation failed (\(installationReason)); restoring the original manifest also failed (\(error.localizedDescription))."
                )
            }
        }
    }

    private func availableMigrationBackup(
        in layout: WorkspacePackageLayout
    ) -> URL? {
        guard Workspace.currentSchemaVersion > WorkspaceManifestMigrator.oldestSupportedSchemaVersion
        else { return nil }

        for version in stride(
            from: Workspace.currentSchemaVersion - 1,
            through: WorkspaceManifestMigrator.oldestSupportedSchemaVersion,
            by: -1
        ) {
            let candidate = layout.migrationBackupURL(forSchemaVersion: version)
            guard fileManager.fileExists(atPath: candidate.path),
                  let data = try? Data(contentsOf: candidate, options: [.mappedIfSafe]),
                  let manifestVersion = try? JSONDecoder().decode(ManifestVersion.self, from: data),
                  manifestVersion.schemaVersion == version,
                  (try? JSONDecoder().decode(Workspace.self, from: data)) != nil
            else { continue }
            return candidate
        }
        return nil
    }

    private func validatePackageDirectory(at packageURL: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: packageURL.path, isDirectory: &isDirectory) else {
            throw WorkspacePackageRepositoryError.packageNotFound(packageURL)
        }
        guard isDirectory.boolValue else {
            throw WorkspacePackageRepositoryError.packageIsNotDirectory(packageURL)
        }
    }

    private func regularFiles(
        in directoryURL: URL,
        relativeTo packageURL: URL
    ) throws -> [String: Int64] {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [:] }
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [:] }

        let packagePath = packageURL.standardizedFileURL.path.hasSuffix("/")
            ? packageURL.standardizedFileURL.path
            : packageURL.standardizedFileURL.path + "/"
        var result: [String: Int64] = [:]
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let standardized = fileURL.standardizedFileURL
            guard standardized.path.hasPrefix(packagePath) else { continue }
            let relativePath = String(standardized.path.dropFirst(packagePath.count))
            result[relativePath] = Int64(values.fileSize ?? 0)
        }
        return result
    }

    private func migrationBackupAssetPaths(in layout: WorkspacePackageLayout) -> Set<String> {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: layout.migrationBackupsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result = Set<String>()
        for url in urls where url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
                  let object = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }
            Self.collectAssetPaths(from: object, into: &result)
        }
        return result
    }

    private static func collectAssetPaths(from object: Any, into result: inout Set<String>) {
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                if (key == "relativePath" || key == "thumbnailRelativePath"),
                   let path = value as? String,
                   isCleanupManagedPath(path) {
                    result.insert(path)
                } else {
                    collectAssetPaths(from: value, into: &result)
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                collectAssetPaths(from: value, into: &result)
            }
        }
    }

    private static func isCleanupManagedPath(_ relativePath: String) -> Bool {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.contains("\\"),
              !relativePath.split(separator: "/").contains("..") else {
            return false
        }
        return relativePath.hasPrefix(
            "\(WorkspacePackageLayout.assetsDirectoryName)/\(WorkspacePackageLayout.derivedAssetsDirectoryName)/"
        ) || relativePath.hasPrefix("\(WorkspacePackageLayout.thumbnailsDirectoryName)/")
    }

    private static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    private static func isMaskArtifactPath(_ relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0] == Substring(WorkspacePackageLayout.assetsDirectoryName),
              components[1] == Substring(WorkspacePackageLayout.derivedAssetsDirectoryName) else {
            return false
        }
        let fileName = components[2].lowercased()
        return fileName.hasPrefix("mask-") && fileName.hasSuffix(".png")
    }

    private func managedAssetURL(
        relativePath: String,
        packageURL: URL
    ) throws -> URL {
        let layout = WorkspacePackageLayout(packageURL: packageURL)
        try validatePackageDirectory(at: layout.packageURL)
        let assetURL = layout.packageURL
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        let packagePath = layout.packageURL.path.hasSuffix("/")
            ? layout.packageURL.path
            : layout.packageURL.path + "/"
        guard assetURL.path.hasPrefix(packagePath) else {
            throw WorkspacePackageRepositoryError.originalAssetImportFailed(
                assetURL,
                reason: "Asset path escapes the workspace package."
            )
        }
        return assetURL
    }

    private func removeStagingPackageIfPresent(at stagingURL: URL) throws {
        if fileManager.fileExists(atPath: stagingURL.path) {
            try fileManager.removeItem(at: stagingURL)
        }
    }

    private func removeItemIfPresent(at url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func destinationForImport(
        in directoryURL: URL,
        baseName: String,
        canonicalExtension: String,
        expectedContentHash: String?
    ) throws -> (url: URL, wasDeduplicated: Bool) {
        var suffix = 1

        while true {
            let suffixText = suffix == 1 ? "" : "-\(suffix)"
            let fileName = "\(baseName)\(suffixText).\(canonicalExtension)"
            let candidate = directoryURL.appendingPathComponent(fileName, isDirectory: false)

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory) else {
                return (candidate, false)
            }

            let candidateAttributes = try? fileManager.attributesOfItem(atPath: candidate.path)
            if !isDirectory.boolValue,
               candidateAttributes?[.type] as? FileAttributeType == .typeRegular,
               let expectedContentHash,
               try sha256ContentHash(for: candidate) == expectedContentHash {
                return (candidate, true)
            }

            suffix += 1
        }
    }

    private func sha256ContentHash(for url: URL) throws -> String? {
        #if canImport(CryptoKit)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return "sha256:\(digest)"
        #else
        return nil
        #endif
    }

    private func sha256ContentHash(for data: Data) -> String? {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "sha256:\(digest)"
        #else
        return nil
        #endif
    }

    private static func fileSystemHashComponent(from contentHash: String) -> String {
        contentHash.replacingOccurrences(of: ":", with: "-")
    }

    private static func sanitizedStem(from sourceURL: URL) -> String {
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = stem.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "-"
        }.joined()
        let collapsed = sanitized.replacingOccurrences(
            of: "-+",
            with: "-",
            options: .regularExpression
        ).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? "asset" : collapsed
    }

    private static func importResult(
        source: URL,
        destinationURL: URL,
        mediaType: OriginalAssetMediaType,
        contentHash: String?,
        wasDeduplicated: Bool
    ) -> OriginalAssetImportResult {
        OriginalAssetImportResult(
            fileName: source.lastPathComponent,
            relativePath: [
                WorkspacePackageLayout.assetsDirectoryName,
                WorkspacePackageLayout.originalAssetsDirectoryName,
                destinationURL.lastPathComponent
            ].joined(separator: "/"),
            mimeType: mediaType.mimeType,
            pixelSize: ImagePixelSizeReader.pixelSize(at: destinationURL),
            contentHash: contentHash,
            wasDeduplicated: wasDeduplicated
        )
    }

    private static func decodingReason(for error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }

        switch decodingError {
        case .dataCorrupted(let context):
            return context.debugDescription
        case .keyNotFound(let key, let context):
            return "Missing key '\(key.stringValue)': \(context.debugDescription)"
        case .typeMismatch(let type, let context):
            return "Invalid \(type): \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "Missing \(type): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    private struct ManifestVersion: Decodable {
        let schemaVersion: Int
    }

    private struct OriginalAssetMediaType: Sendable {
        let mimeType: String
        let canonicalExtension: String
    }

    private static let supportedOriginalAssetTypes: [String: OriginalAssetMediaType] = [
        "png": OriginalAssetMediaType(mimeType: "image/png", canonicalExtension: "png"),
        "jpg": OriginalAssetMediaType(mimeType: "image/jpeg", canonicalExtension: "jpg"),
        "jpeg": OriginalAssetMediaType(mimeType: "image/jpeg", canonicalExtension: "jpg"),
        "heic": OriginalAssetMediaType(mimeType: "image/heic", canonicalExtension: "heic"),
        "webp": OriginalAssetMediaType(mimeType: "image/webp", canonicalExtension: "webp"),
        "mov": OriginalAssetMediaType(mimeType: "video/quicktime", canonicalExtension: "mov"),
        "mp4": OriginalAssetMediaType(mimeType: "video/mp4", canonicalExtension: "mp4"),
        "m4v": OriginalAssetMediaType(mimeType: "video/x-m4v", canonicalExtension: "m4v")
    ]
}
