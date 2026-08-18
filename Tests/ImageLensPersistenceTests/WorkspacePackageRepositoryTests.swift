import Foundation
import ImageLensCore
import XCTest
@testable import ImageLensPersistence

@MainActor
final class WorkspacePackageRepositoryTests: XCTestCase {
    func testSaveAndLoadRoundTrip() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let packageURL = temporaryDirectory.appendingPathComponent("RoundTrip.imagelens", isDirectory: true)
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let asset = Asset(
            kind: .source,
            state: .ready,
            displayName: "Reference.png",
            relativePath: "assets/original/reference.png",
            thumbnailRelativePath: "thumbnails/reference.jpg",
            mimeType: "image/png",
            pixelSize: PixelSize(width: 2048, height: 1536),
            contentHash: "sha256:test",
            createdAt: timestamp
        )
        let workspace = Workspace(
            title: "Round-trip workspace",
            assets: [asset],
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let repository = WorkspacePackageRepository()

        try await repository.save(workspace, to: packageURL)
        let loaded = try await repository.load(from: packageURL)

        XCTAssertEqual(loaded, workspace)
    }

    func testCorruptManifestProducesExplicitError() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let packageURL = temporaryDirectory.appendingPathComponent("Corrupt.imagelens", isDirectory: true)
        let layout = WorkspacePackageLayout(packageURL: packageURL)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        try Data("{ definitely not JSON".utf8).write(to: layout.manifestURL)
        let repository = WorkspacePackageRepository()

        do {
            _ = try await repository.load(from: packageURL)
            XCTFail("Expected a corrupt manifest error")
        } catch let error as WorkspacePackageRepositoryError {
            guard case .corruptManifest(let manifestURL, let reason) = error else {
                return XCTFail("Unexpected repository error: \(error)")
            }
            XCTAssertEqual(manifestURL, layout.manifestURL)
            XCTAssertFalse(reason.isEmpty)
        }
    }

    func testSaveCreatesRequiredLayoutAndPreservesAssetsAcrossReplacement() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let packageURL = temporaryDirectory.appendingPathComponent("Layout.imagelens", isDirectory: true)
        let layout = WorkspacePackageLayout(packageURL: packageURL)
        let repository = WorkspacePackageRepository()

        try await repository.save(Workspace(title: "First"), to: packageURL)

        assertDirectoryExists(layout.assetsURL)
        assertDirectoryExists(layout.originalAssetsURL)
        assertDirectoryExists(layout.derivedAssetsURL)
        assertDirectoryExists(layout.thumbnailsURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.manifestURL.path))

        let preservedAssetURL = layout.originalAssetsURL.appendingPathComponent("preserved.bin")
        let preservedData = Data([0x01, 0x02, 0x03, 0x04])
        try preservedData.write(to: preservedAssetURL)

        try await repository.save(Workspace(title: "Second"), to: packageURL)

        XCTAssertEqual(try Data(contentsOf: preservedAssetURL), preservedData)
        let reloadedWorkspace = try await repository.load(from: packageURL)
        XCTAssertEqual(reloadedWorkspace.title, "Second")

        let manifestObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: layout.manifestURL)) as? [String: Any]
        )
        XCTAssertEqual(manifestObject["schemaVersion"] as? Int, Workspace.currentSchemaVersion)
    }

    func testClonePackageCopiesAssetsAndWritesIndependentManifest() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let sourceURL = temporaryDirectory.appendingPathComponent("Source.imagelens", isDirectory: true)
        let cloneURL = temporaryDirectory.appendingPathComponent("Clone.imagelens", isDirectory: true)
        let repository = WorkspacePackageRepository()
        let original = Workspace(title: "Source")
        try await repository.save(original, to: sourceURL)

        let sourceAssetURL = WorkspacePackageLayout(packageURL: sourceURL)
            .originalAssetsURL.appendingPathComponent("reference.bin")
        try Data([0xCA, 0xFE]).write(to: sourceAssetURL)

        var clone = original
        clone.id = WorkspaceID()
        clone.title = "Clone"
        clone.createdAt = .now
        clone.updatedAt = clone.createdAt
        try await repository.clonePackage(from: sourceURL, to: cloneURL, workspace: clone)

        let loadedClone = try await repository.load(from: cloneURL)
        XCTAssertEqual(loadedClone, clone)
        XCTAssertEqual(
            try Data(contentsOf: WorkspacePackageLayout(packageURL: cloneURL)
                .originalAssetsURL.appendingPathComponent("reference.bin")),
            Data([0xCA, 0xFE])
        )
        let loadedOriginal = try await repository.load(from: sourceURL)
        XCTAssertEqual(loadedOriginal, original)
    }

    func testCreatePackageReplacesExistingProjectWithoutKeepingItsAssets() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let packageURL = temporaryDirectory.appendingPathComponent("Replace.imagelens", isDirectory: true)
        let repository = WorkspacePackageRepository()
        try await repository.save(Workspace(title: "Old"), to: packageURL)
        let oldAssetURL = WorkspacePackageLayout(packageURL: packageURL)
            .originalAssetsURL.appendingPathComponent("old.bin")
        try Data([0x01]).write(to: oldAssetURL)

        let replacement = Workspace(title: "New")
        try await repository.createPackage(replacement, at: packageURL)

        let loadedReplacement = try await repository.load(from: packageURL)
        XCTAssertEqual(loadedReplacement, replacement)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldAssetURL.path))
    }

    func testUnsupportedManifestVersionIsRejectedBeforeWorkspaceDecode() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let packageURL = temporaryDirectory.appendingPathComponent("Future.imagelens", isDirectory: true)
        let layout = WorkspacePackageLayout(packageURL: packageURL)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        try Data("{\"schemaVersion\": 999}".utf8).write(to: layout.manifestURL)
        let repository = WorkspacePackageRepository()

        do {
            _ = try await repository.load(from: packageURL)
            XCTFail("Expected an unsupported schema error")
        } catch let error as WorkspacePackageRepositoryError {
            XCTAssertEqual(
                error,
                .unsupportedSchemaVersion(found: 999, supported: Workspace.currentSchemaVersion)
            )
        }
    }

    func testLoadV1ManifestMigratesPersistsAndBacksUpOriginalBytes() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let packageURL = temporaryDirectory.appendingPathComponent(
            "Legacy.imagelens",
            isDirectory: true
        )
        let layout = WorkspacePackageLayout(packageURL: packageURL)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        for directoryURL in layout.requiredDirectoryURLs {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        let generationID = GenerationID()
        let generated = Asset(
            kind: .generated,
            state: .ready,
            displayName: "result.webp",
            relativePath: "assets/derived/shared.webp",
            mimeType: "image/webp",
            contentHash: "sha256:shared",
            sourceGenerationID: generationID
        )
        let extractedAlias = Asset(
            kind: .source,
            state: .imported,
            isSavedToLibrary: true,
            displayName: "material.webp",
            relativePath: generated.relativePath,
            mimeType: generated.mimeType,
            contentHash: generated.contentHash
        )
        var legacyWorkspace = Workspace(
            title: "Legacy",
            assets: [generated, extractedAlias]
        )
        legacyWorkspace.schemaVersion = 1
        let originalData = try legacyV1Data(for: legacyWorkspace)
        try originalData.write(to: layout.manifestURL)
        let assetData = Data("do-not-touch".utf8)
        let assetURL = layout.packageURL.appendingPathComponent(generated.relativePath)
        try assetData.write(to: assetURL)

        let repository = WorkspacePackageRepository()
        let migrated = try await repository.load(from: packageURL)

        XCTAssertEqual(migrated.schemaVersion, Workspace.currentSchemaVersion)
        XCTAssertEqual(migrated.assets[0].provenance, .generated)
        XCTAssertEqual(migrated.assets[0].usages, [.result])
        XCTAssertEqual(migrated.assets[1].provenance, .generated)
        XCTAssertEqual(migrated.assets[1].usages, [.material])
        XCTAssertEqual(migrated.assets[1].sourceGenerationID, generationID)
        XCTAssertEqual(try Data(contentsOf: assetURL), assetData)

        let backupURL = layout.migrationBackupURL(forSchemaVersion: 1)
        XCTAssertEqual(try Data(contentsOf: backupURL), originalData)
        let installedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: layout.manifestURL))
                as? [String: Any]
        )
        XCTAssertEqual(
            installedObject["schemaVersion"] as? Int,
            Workspace.currentSchemaVersion
        )

        let backupBeforeSecondLoad = try Data(contentsOf: backupURL)
        let secondLoad = try await repository.load(from: packageURL)
        XCTAssertEqual(secondLoad, migrated)
        XCTAssertEqual(try Data(contentsOf: backupURL), backupBeforeSecondLoad)
    }

    func testBundledLegacyV1GoldenManifestMigratesWithoutChangingIdentityOrLayout() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let fixtureURL = try XCTUnwrap(
            Bundle.module.url(
                forResource: "LegacyV1",
                withExtension: nil,
                subdirectory: "Fixtures"
            )
        )
        let packageURL = temporaryDirectory.appendingPathComponent(
            "Golden.imagelens",
            isDirectory: true
        )
        try FileManager.default.copyItem(at: fixtureURL, to: packageURL)
        let originalManifest = try Data(
            contentsOf: WorkspacePackageLayout(packageURL: packageURL).manifestURL
        )

        let repository = WorkspacePackageRepository()
        let workspace = try await repository.load(from: packageURL)

        XCTAssertEqual(workspace.schemaVersion, Workspace.currentSchemaVersion)
        XCTAssertEqual(
            workspace.id.rawValue.uuidString,
            "00000000-0000-0000-0000-000000000001"
        )
        XCTAssertEqual(workspace.assets.map(\.id.rawValue.uuidString), [
            "00000000-0000-0000-0000-000000001001",
            "00000000-0000-0000-0000-000000001002"
        ])
        XCTAssertEqual(workspace.assets[0].usages, [.result])
        XCTAssertEqual(workspace.assets[1].provenance, .generated)
        XCTAssertEqual(workspace.assets[1].usages, [.material])
        XCTAssertEqual(
            workspace.assets[1].sourceGenerationID?.rawValue.uuidString,
            "00000000-0000-0000-0000-000000007001"
        )
        XCTAssertEqual(workspace.canvasNodes.count, 1)
        XCTAssertEqual(workspace.canvasNodes[0].frame, WorldRect(
            x: 120,
            y: 80,
            width: 320,
            height: 320
        ))

        let backupURL = WorkspacePackageLayout(packageURL: packageURL)
            .migrationBackupURL(forSchemaVersion: 1)
        XCTAssertEqual(try Data(contentsOf: backupURL), originalManifest)
    }

    func testCurrentManifestDoesNotCreateMigrationBackup() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let packageURL = temporaryDirectory.appendingPathComponent(
            "Current.imagelens",
            isDirectory: true
        )
        let repository = WorkspacePackageRepository()
        try await repository.save(Workspace(title: "Current"), to: packageURL)

        _ = try await repository.load(from: packageURL)

        let layout = WorkspacePackageLayout(packageURL: packageURL)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: layout.migrationBackupsURL.path)
        )
    }

    func testManagedAssetExportCopiesBytesWithoutChangingSource() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let packageURL = temporaryDirectory.appendingPathComponent("Export.imagelens", isDirectory: true)
        let repository = WorkspacePackageRepository()
        try await repository.save(Workspace(title: "Export"), to: packageURL)
        let bytes = Data("generated-video".utf8)
        let written = try await repository.writeDerivedAsset(
            bytes,
            mimeType: "video/mp4",
            generationID: GenerationID(),
            index: 0,
            into: packageURL
        )
        let destination = temporaryDirectory.appendingPathComponent("Result.mp4")

        try await repository.exportManagedAsset(
            relativePath: written.relativePath,
            from: packageURL,
            to: destination
        )

        XCTAssertEqual(try Data(contentsOf: destination), bytes)
        let sourceBytes = try await repository.readAssetData(
            relativePath: written.relativePath,
            from: packageURL
        )
        XCTAssertEqual(sourceBytes, bytes)
    }

    func testManagedAssetExportRejectsProjectInternalDestination() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let packageURL = temporaryDirectory.appendingPathComponent("Export.imagelens", isDirectory: true)
        let repository = WorkspacePackageRepository()
        try await repository.save(Workspace(title: "Export"), to: packageURL)
        let written = try await repository.writeDerivedAsset(
            Data("image".utf8),
            mimeType: "image/png",
            generationID: GenerationID(),
            index: 0,
            into: packageURL
        )
        let destination = packageURL.appendingPathComponent("manual-export.png")

        do {
            try await repository.exportManagedAsset(
                relativePath: written.relativePath,
                from: packageURL,
                to: destination
            )
            XCTFail("Expected an internal destination to be rejected")
        } catch let error as WorkspacePackageRepositoryError {
            guard case .writeFailed(let url, _) = error else {
                return XCTFail("Unexpected repository error: \(error)")
            }
            XCTAssertEqual(url, destination.standardizedFileURL)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testStorageCleanupPlanProtectsSharedPathsAndFindsOrphans() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let packageURL = temporaryDirectory.appendingPathComponent("Cleanup.imagelens", isDirectory: true)
        let repository = WorkspacePackageRepository()
        let removable = Asset(
            kind: .generated,
            state: .ready,
            displayName: "Unused",
            relativePath: "assets/derived/unused.png",
            mimeType: "image/png"
        )
        let shared = Asset(
            kind: .generated,
            state: .ready,
            displayName: "Shared",
            relativePath: "assets/derived/shared.png",
            mimeType: "image/png"
        )
        let alias = shared.sourceMaterialAlias()
        let generation = GenerationRecord(
            recipeID: RecipeID(),
            promptSnapshotID: CompiledPromptID(),
            providerID: ProviderID("gemini"),
            modelID: "model",
            aspectRatio: "16:9",
            state: .succeeded,
            outputAssetIDs: [removable.id, shared.id]
        )
        let workspace = Workspace(
            title: "Cleanup",
            assets: [removable, shared, alias],
            generations: [generation]
        )
        try await repository.save(workspace, to: packageURL)
        let layout = WorkspacePackageLayout(packageURL: packageURL)
        try Data(repeating: 1, count: 10).write(
            to: layout.derivedAssetsURL.appendingPathComponent("unused.png")
        )
        try Data(repeating: 2, count: 20).write(
            to: layout.derivedAssetsURL.appendingPathComponent("shared.png")
        )
        try Data(repeating: 3, count: 30).write(
            to: layout.derivedAssetsURL.appendingPathComponent("orphan.png")
        )

        let plan = try await repository.storageCleanupPlan(for: workspace, at: packageURL)

        XCTAssertEqual(plan.removableAssetIDs, [removable.id])
        XCTAssertEqual(plan.removableRelativePaths, ["assets/derived/unused.png"])
        XCTAssertEqual(plan.orphanRelativePaths, ["assets/derived/orphan.png"])
        XCTAssertEqual(plan.reclaimableBytes, 40)

        let cleaned = WorkspaceStorageCleanupPolicy.removingGeneratedAssets(
            Set(plan.removableAssetIDs),
            from: workspace
        )
        try await repository.save(cleaned, to: packageURL)
        try await repository.removeCleanupFiles(
            relativePaths: plan.removableRelativePaths + plan.orphanRelativePaths,
            from: packageURL
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.derivedAssetsURL.appendingPathComponent("unused.png").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.derivedAssetsURL.appendingPathComponent("orphan.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: layout.derivedAssetsURL.appendingPathComponent("shared.png").path))
        XCTAssertEqual(cleaned.assets.map(\.id), [shared.id, alias.id])
        XCTAssertEqual(cleaned.generations[0].outputAssetIDs, [shared.id])
    }

    func testCorruptMigratedManifestReportsRecoveryBackupWithoutOverwritingIt() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let packageURL = temporaryDirectory.appendingPathComponent(
            "Recoverable.imagelens",
            isDirectory: true
        )
        let layout = WorkspacePackageLayout(packageURL: packageURL)
        try FileManager.default.createDirectory(
            at: layout.migrationBackupsURL,
            withIntermediateDirectories: true
        )
        let backupURL = layout.migrationBackupURL(forSchemaVersion: 1)
        var legacyWorkspace = Workspace(title: "Recoverable")
        legacyWorkspace.schemaVersion = 1
        let backupData = try legacyV1Data(for: legacyWorkspace)
        try backupData.write(to: backupURL)
        try Data("{\"schemaVersion\":\(Workspace.currentSchemaVersion)}".utf8)
            .write(to: layout.manifestURL)
        let repository = WorkspacePackageRepository()

        do {
            _ = try await repository.load(from: packageURL)
            XCTFail("Expected recovery information")
        } catch let error as WorkspacePackageRepositoryError {
            guard case .migrationRecoveryAvailable(let manifest, let backup, _) = error else {
                return XCTFail("Unexpected repository error: \(error)")
            }
            XCTAssertEqual(manifest, layout.manifestURL)
            XCTAssertEqual(backup, backupURL)
        }
        XCTAssertEqual(try Data(contentsOf: backupURL), backupData)
    }

    func testV1ProjectStillOpensInMemoryWhenMigrationCannotBePersisted() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let packageURL = temporaryDirectory.appendingPathComponent(
            "ReadOnlyMigration.imagelens",
            isDirectory: true
        )
        let layout = WorkspacePackageLayout(packageURL: packageURL)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        var legacyWorkspace = Workspace(title: "Read-only legacy")
        legacyWorkspace.schemaVersion = 1
        let originalData = try legacyV1Data(for: legacyWorkspace)
        try originalData.write(to: layout.manifestURL)
        // A regular file at the backup directory path deterministically makes
        // migration installation fail without depending on filesystem permissions.
        try Data("blocked".utf8).write(to: layout.migrationBackupsURL)

        let repository = WorkspacePackageRepository()
        let loaded = try await repository.load(from: packageURL)

        XCTAssertEqual(loaded.schemaVersion, Workspace.currentSchemaVersion)
        XCTAssertEqual(loaded.id, legacyWorkspace.id)
        XCTAssertEqual(try Data(contentsOf: layout.manifestURL), originalData)
    }

    func testV2ProjectMigratesToV3WithEmptyTextBlocksAndExactBackup() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let packageURL = temporaryDirectory.appendingPathComponent(
            "LegacyV2.imagelens",
            isDirectory: true
        )
        let layout = WorkspacePackageLayout(packageURL: packageURL)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let instruction = PromptModule(
            role: .instruction,
            content: "Preserve this instruction",
            evidence: .userProvided
        )
        let node = CanvasNode(
            promptModuleID: instruction.id,
            frame: WorldRect(x: 20, y: 40, width: 280, height: 160)
        )
        var legacy = Workspace(
            title: "Legacy v2",
            promptModules: [instruction],
            canvasNodes: [node]
        )
        legacy.schemaVersion = 2
        let originalData = try legacyV2Data(for: legacy)
        try originalData.write(to: layout.manifestURL)

        let migrated = try await WorkspacePackageRepository().load(from: packageURL)

        XCTAssertEqual(migrated.schemaVersion, Workspace.currentSchemaVersion)
        XCTAssertEqual(migrated.promptModules, [instruction])
        XCTAssertEqual(migrated.canvasNodes, [node])
        XCTAssertTrue(migrated.textBlocks.isEmpty)
        XCTAssertEqual(
            try Data(contentsOf: layout.migrationBackupURL(forSchemaVersion: 2)),
            originalData
        )
    }

    func testV3ProjectMigratesToV4WithoutChangingReferenceBindings() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let packageURL = temporaryDirectory.appendingPathComponent(
            "LegacyV3.imagelens",
            isDirectory: true
        )
        let layout = WorkspacePackageLayout(packageURL: packageURL)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let asset = Asset(
            kind: .source,
            displayName: "reference.png",
            relativePath: "assets/original/reference.png",
            mimeType: "image/png"
        )
        let target = CompileTarget(providerID: ProviderID("gemini"), modelID: "image")
        let recipe = Recipe(name: "Input", target: target)
        let binding = GeneratorAssetBinding(assetID: asset.id, role: .style, order: 0)
        let generator = Generator(
            name: "Image action",
            recipeID: recipe.id,
            target: target,
            assetBindings: [binding]
        )
        var legacy = Workspace(
            title: "Legacy v3",
            assets: [asset],
            recipes: [recipe],
            generators: [generator]
        )
        legacy.schemaVersion = 3
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let originalData = try encoder.encode(legacy)
        try originalData.write(to: layout.manifestURL)

        let migrated = try await WorkspacePackageRepository().load(from: packageURL)

        XCTAssertEqual(migrated.schemaVersion, Workspace.currentSchemaVersion)
        XCTAssertEqual(migrated.generators.first?.assetBindings, [binding])
        XCTAssertEqual(
            try Data(contentsOf: layout.migrationBackupURL(forSchemaVersion: 3)),
            originalData
        )
    }

    func testV4ProjectMigratesToV5WithImageGenerationDefaults() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let packageURL = temporaryDirectory.appendingPathComponent(
            "LegacyV4.imagelens",
            isDirectory: true
        )
        let layout = WorkspacePackageLayout(packageURL: packageURL)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let target = CompileTarget(providerID: "gemini", modelID: "image")
        let recipe = Recipe(name: "Image", target: target)
        let generator = Generator(name: "Image", recipeID: recipe.id, target: target)
        let generation = GenerationRecord(
            generatorID: generator.id,
            recipeID: recipe.id,
            promptSnapshotID: CompiledPromptID(),
            providerID: target.providerID,
            modelID: target.modelID,
            aspectRatio: "16:9",
            state: .succeeded
        )
        var legacy = Workspace(
            title: "Legacy v4",
            recipes: [recipe],
            generators: [generator],
            generations: [generation]
        )
        legacy.schemaVersion = 4
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(legacy)) as? [String: Any]
        )
        var generators = try XCTUnwrap(object["generators"] as? [[String: Any]])
        generators[0].removeValue(forKey: "mediaKind")
        object["generators"] = generators
        var generations = try XCTUnwrap(object["generations"] as? [[String: Any]])
        generations[0].removeValue(forKey: "mediaKind")
        object["generations"] = generations
        let originalData = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try originalData.write(to: layout.manifestURL)

        let migrated = try await WorkspacePackageRepository().load(from: packageURL)

        XCTAssertEqual(migrated.schemaVersion, 5)
        XCTAssertEqual(migrated.generators.first?.mediaKind, .image)
        XCTAssertEqual(migrated.generations.first?.mediaKind, .image)
        XCTAssertEqual(
            try Data(contentsOf: layout.migrationBackupURL(forSchemaVersion: 4)),
            originalData
        )
    }

    func testExistingDifferentMigrationBackupIsNeverOverwritten() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let packageURL = temporaryDirectory.appendingPathComponent(
            "StaleBackup.imagelens",
            isDirectory: true
        )
        let layout = WorkspacePackageLayout(packageURL: packageURL)
        try FileManager.default.createDirectory(
            at: layout.migrationBackupsURL,
            withIntermediateDirectories: true
        )
        var legacyWorkspace = Workspace(title: "Current legacy")
        legacyWorkspace.schemaVersion = 1
        let originalData = try legacyV1Data(for: legacyWorkspace)
        try originalData.write(to: layout.manifestURL)

        var olderWorkspace = legacyWorkspace
        olderWorkspace.title = "Older legacy"
        let olderBackup = try legacyV1Data(for: olderWorkspace)
        let backupURL = layout.migrationBackupURL(forSchemaVersion: 1)
        try olderBackup.write(to: backupURL)

        let repository = WorkspacePackageRepository()
        let loaded = try await repository.load(from: packageURL)

        XCTAssertEqual(loaded.schemaVersion, Workspace.currentSchemaVersion)
        XCTAssertEqual(loaded.title, legacyWorkspace.title)
        XCTAssertEqual(try Data(contentsOf: layout.manifestURL), originalData)
        XCTAssertEqual(try Data(contentsOf: backupURL), olderBackup)
    }

    func testSaveRejectsLegacyInMemoryWorkspace() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let packageURL = temporaryDirectory.appendingPathComponent(
            "LegacySave.imagelens",
            isDirectory: true
        )
        var workspace = Workspace(title: "Legacy")
        workspace.schemaVersion = 1
        let repository = WorkspacePackageRepository()

        do {
            try await repository.save(workspace, to: packageURL)
            XCTFail("Expected a schema version error")
        } catch let error as WorkspacePackageRepositoryError {
            XCTAssertEqual(
                error,
                .unsupportedSchemaVersion(
                    found: 1,
                    supported: Workspace.currentSchemaVersion
                )
            )
        }
    }

    func testClipboardAndGeneratedAssetsRoundTripThroughManagedStorage() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let packageURL = temporaryDirectory.appendingPathComponent("Assets.imagelens", isDirectory: true)
        let repository = WorkspacePackageRepository()
        try await repository.save(Workspace(title: "Assets"), to: packageURL)

        let clipboardData = Data([0x89, 0x50, 0x4E, 0x47])
        let original = try await repository.importOriginalAssetData(
            clipboardData,
            mimeType: "image/png",
            suggestedName: "Clipboard.png",
            into: packageURL
        )
        let duplicate = try await repository.importOriginalAssetData(
            clipboardData,
            mimeType: "image/png",
            suggestedName: "Again.png",
            into: packageURL
        )
        XCTAssertEqual(original.relativePath, duplicate.relativePath)
        XCTAssertTrue(duplicate.wasDeduplicated)
        let reloadedClipboard = try await repository.readAssetData(
            relativePath: original.relativePath,
            from: packageURL
        )
        XCTAssertEqual(reloadedClipboard, clipboardData)

        do {
            _ = try await repository.importOriginalAssetData(
                Data("movie bytes".utf8),
                mimeType: "video/mp4",
                suggestedName: "Clipboard.mp4",
                into: packageURL
            )
            XCTFail("Expected clipboard data import to reject non-image media")
        } catch let error as WorkspacePackageRepositoryError {
            guard case let .originalAssetImportFailed(_, reason) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(reason, "Clipboard data import only accepts image content.")
        }

        let generatedData = Data("generated image".utf8)
        let generated = try await repository.writeDerivedAsset(
            generatedData,
            mimeType: "image/webp",
            generationID: GenerationID(),
            index: 0,
            into: packageURL
        )
        XCTAssertTrue(generated.relativePath.hasPrefix("assets/derived/generation-"))
        XCTAssertTrue(generated.relativePath.hasSuffix(".webp"))
        let reloadedGenerated = try await repository.readAssetData(
            relativePath: generated.relativePath,
            from: packageURL
        )
        XCTAssertEqual(reloadedGenerated, generatedData)

        let generatedVideoData = Data("generated video".utf8)
        let generatedVideo = try await repository.writeDerivedAsset(
            generatedVideoData,
            mimeType: "video/mp4",
            generationID: GenerationID(),
            index: 0,
            into: packageURL
        )
        XCTAssertTrue(generatedVideo.relativePath.hasPrefix("assets/derived/generation-"))
        XCTAssertTrue(generatedVideo.relativePath.hasSuffix(".mp4"))
        XCTAssertEqual(generatedVideo.mimeType, "video/mp4")
        let reloadedGeneratedVideo = try await repository.readAssetData(
            relativePath: generatedVideo.relativePath,
            from: packageURL
        )
        XCTAssertEqual(reloadedGeneratedVideo, generatedVideoData)
    }

    func testMaskArtifactRoundTripsInsideDerivedStorageAndDeduplicates() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let packageURL = temporaryDirectory.appendingPathComponent(
            "Mask.imagelens",
            isDirectory: true
        )
        let repository = WorkspacePackageRepository()
        try await repository.save(Workspace(title: "Mask"), to: packageURL)
        let generatorID = GeneratorID(
            try XCTUnwrap(UUID(uuidString: "10000000-0000-0000-0000-000000000001"))
        )
        let sourceAssetID = AssetID(
            try XCTUnwrap(UUID(uuidString: "20000000-0000-0000-0000-000000000002"))
        )
        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02])

        let first = try await repository.writeMaskArtifact(
            pngData,
            generatorID: generatorID,
            sourceAssetID: sourceAssetID,
            into: packageURL
        )
        let duplicate = try await repository.writeMaskArtifact(
            pngData,
            generatorID: generatorID,
            sourceAssetID: sourceAssetID,
            into: packageURL
        )

        XCTAssertEqual(first, duplicate)
        XCTAssertNotNil(first.contentHash)
        XCTAssertTrue(first.relativePath.hasPrefix("assets/derived/mask-"))
        XCTAssertTrue(first.relativePath.hasSuffix(".png"))
        XCTAssertTrue(first.relativePath.contains(generatorID.rawValue.uuidString.lowercased()))
        XCTAssertTrue(first.relativePath.contains(sourceAssetID.rawValue.uuidString.lowercased()))
        let reloaded = try await repository.readMaskArtifact(
            relativePath: first.relativePath,
            from: packageURL
        )
        XCTAssertEqual(reloaded, pngData)
        let files = try FileManager.default.contentsOfDirectory(
            at: WorkspacePackageLayout(packageURL: packageURL).derivedAssetsURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(files.filter { $0.pathExtension == "png" }.count, 1)
    }

    func testMaskArtifactRejectsNonPNGDataAndNonDerivedReadPaths() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let packageURL = temporaryDirectory.appendingPathComponent(
            "MaskBoundary.imagelens",
            isDirectory: true
        )
        let repository = WorkspacePackageRepository()
        try await repository.save(Workspace(title: "Mask boundary"), to: packageURL)

        do {
            _ = try await repository.writeMaskArtifact(
                Data("not a png".utf8),
                generatorID: GeneratorID(),
                sourceAssetID: AssetID(),
                into: packageURL
            )
            XCTFail("Expected non-PNG mask data to be rejected")
        } catch let error as WorkspacePackageRepositoryError {
            guard case let .writeFailed(url, reason) = error else {
                return XCTFail("Unexpected repository error: \(error)")
            }
            XCTAssertEqual(url, WorkspacePackageLayout(packageURL: packageURL).derivedAssetsURL)
            XCTAssertEqual(reason, "Mask artifact must contain non-empty PNG data.")
        }

        let original = try await repository.importOriginalAssetData(
            Data([0x89, 0x50, 0x4E, 0x47]),
            mimeType: "image/png",
            suggestedName: "Original.png",
            into: packageURL
        )
        do {
            _ = try await repository.readMaskArtifact(
                relativePath: original.relativePath,
                from: packageURL
            )
            XCTFail("Expected an original-asset path to be rejected")
        } catch let error as WorkspacePackageRepositoryError {
            guard case let .managedAssetUnavailable(_, reason) = error else {
                return XCTFail("Unexpected repository error: \(error)")
            }
            XCTAssertEqual(
                reason,
                "Mask artifacts must be PNG files stored directly in assets/derived."
            )
        }
    }

    func testManagedAssetURLRejectsEscapesSymlinksAndDirectories() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let packageURL = temporaryDirectory.appendingPathComponent("Video.imagelens", isDirectory: true)
        let repository = WorkspacePackageRepository()
        try await repository.save(Workspace(title: "Video"), to: packageURL)
        let layout = WorkspacePackageLayout(packageURL: packageURL)

        let videoURL = layout.originalAssetsURL.appendingPathComponent("clip.mp4")
        try Data([0x00, 0x01]).write(to: videoURL)
        let resolved = try await repository.resolveManagedAssetURL(
            relativePath: "assets/original/clip.mp4",
            from: packageURL
        )
        XCTAssertEqual(resolved, videoURL.resolvingSymlinksInPath().standardizedFileURL)

        let outsideURL = temporaryDirectory.appendingPathComponent("outside.mov")
        try Data([0x02]).write(to: outsideURL)
        let symlinkURL = layout.originalAssetsURL.appendingPathComponent("linked.mov")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: outsideURL)

        for relativePath in ["../outside.mov", "assets/original/linked.mov", "assets/original"] {
            do {
                _ = try await repository.resolveManagedAssetURL(
                    relativePath: relativePath,
                    from: packageURL
                )
                XCTFail("Expected managed asset resolution to reject \(relativePath)")
            } catch let error as WorkspacePackageRepositoryError {
                switch error {
                case .managedAssetUnavailable, .originalAssetImportFailed:
                    break
                default:
                    XCTFail("Unexpected repository error: \(error)")
                }
            }
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ImageLensPersistenceTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func legacyV1Data(for workspace: Workspace) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let encoded = try encoder.encode(workspace)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["schemaVersion"] = 1
        object["assets"] = try XCTUnwrap(object["assets"] as? [[String: Any]]).map { asset in
            var legacyAsset = asset
            legacyAsset.removeValue(forKey: "provenance")
            legacyAsset.removeValue(forKey: "usages")
            return legacyAsset
        }
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    private func legacyV2Data(for workspace: Workspace) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(workspace)) as? [String: Any]
        )
        object["schemaVersion"] = 2
        object.removeValue(forKey: "textBlocks")
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    private func assertDirectoryExists(
        _ url: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var isDirectory: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
            "Expected directory at \(url.path)",
            file: file,
            line: line
        )
        XCTAssertTrue(isDirectory.boolValue, file: file, line: line)
    }
}
