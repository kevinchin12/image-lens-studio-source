import Foundation
import ImageLensCore

struct WorkspaceMigrationResult: Equatable, Sendable {
    var workspace: Workspace
    var sourceVersion: Int
    var destinationVersion: Int
}

enum WorkspaceManifestMigrationError: Error, Equatable, Sendable {
    case unsupportedSourceVersion(Int)
    case missingMigrationStep(Int)
    case preservationCheckFailed(String)
}

enum WorkspaceManifestMigrator {
    static let oldestSupportedSchemaVersion = 1

    static func migrate(
        data: Data,
        sourceVersion: Int,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> WorkspaceMigrationResult {
        guard sourceVersion >= oldestSupportedSchemaVersion,
              sourceVersion <= Workspace.currentSchemaVersion else {
            throw WorkspaceManifestMigrationError.unsupportedSourceVersion(sourceVersion)
        }

        let decodedWorkspace = try decoder.decode(Workspace.self, from: data)
        var workspace = decodedWorkspace
        var version = sourceVersion
        while version < Workspace.currentSchemaVersion {
            switch version {
            case 1:
                workspace = migrateV1ToV2(workspace)
                version = 2
            case 2:
                workspace = try migrateV2ToV3(workspace)
                version = 3
            case 3:
                workspace = try migrateV3ToV4(workspace)
                version = 4
            case 4:
                workspace = try migrateV4ToV5(workspace)
                version = 5
            default:
                throw WorkspaceManifestMigrationError.missingMigrationStep(version)
            }
        }
        workspace.schemaVersion = Workspace.currentSchemaVersion
        try validatePreservation(from: decodedWorkspace, to: workspace)
        return WorkspaceMigrationResult(
            workspace: workspace,
            sourceVersion: sourceVersion,
            destinationVersion: Workspace.currentSchemaVersion
        )
    }

    private static func migrateV1ToV2(_ legacyWorkspace: Workspace) -> Workspace {
        var workspace = legacyWorkspace

        var generationIDsByPath: [String: Set<GenerationID>] = [:]
        for asset in workspace.assets {
            guard asset.kind == .generated,
                  let generationID = asset.sourceGenerationID else { continue }
            generationIDsByPath[asset.relativePath, default: []].insert(generationID)
        }
        let generatedProvenanceByPath = generationIDsByPath.compactMapValues {
            $0.count == 1 ? $0.first : nil
        }

        for index in workspace.assets.indices {
            var asset = workspace.assets[index]
            switch asset.kind {
            case .generated:
                asset.provenance = .generated
                asset.usages = asset.isSavedToLibrary
                    ? [.material, .result]
                    : [.result]
            case .source:
                if let inferredGenerationID = generatedProvenanceByPath[asset.relativePath] {
                    asset.provenance = .generated
                    asset.sourceGenerationID = inferredGenerationID
                } else {
                    asset.provenance = .imported
                }
                asset.usages = [.material]
            }
            workspace.assets[index] = asset
        }

        workspace.schemaVersion = 2
        return workspace
    }

    private static func migrateV2ToV3(_ legacyWorkspace: Workspace) throws -> Workspace {
        var workspace = legacyWorkspace
        // v3 adds independent canvas text blocks. Existing prompt modules
        // retain their exact roles and content, so this step only declares the
        // newer schema contract; the new collection decodes as empty.
        workspace.schemaVersion = 3
        var expected = legacyWorkspace
        expected.schemaVersion = 3
        guard workspace == expected else {
            throw WorkspaceManifestMigrationError.preservationCheckFailed(
                "v2 to v3 workspace values"
            )
        }
        return workspace
    }

    private static func migrateV3ToV4(_ legacyWorkspace: Workspace) throws -> Workspace {
        var workspace = legacyWorkspace
        // v4 introduces the general media-reference role used by direct
        // media-to-action connections. Existing semantic bindings are kept
        // byte-for-byte equivalent and need no conversion.
        workspace.schemaVersion = 4
        var expected = legacyWorkspace
        expected.schemaVersion = 4
        guard workspace == expected else {
            throw WorkspaceManifestMigrationError.preservationCheckFailed(
                "v3 to v4 workspace values"
            )
        }
        return workspace
    }

    private static func migrateV4ToV5(_ legacyWorkspace: Workspace) throws -> Workspace {
        var workspace = legacyWorkspace
        // v5 adds an explicit generation output modality. The v4 decoder
        // supplies `.image`, preserving every existing generator and run.
        workspace.schemaVersion = 5
        var expected = legacyWorkspace
        expected.schemaVersion = 5
        guard workspace == expected else {
            throw WorkspaceManifestMigrationError.preservationCheckFailed(
                "v4 to v5 workspace values"
            )
        }
        return workspace
    }

    private static func validatePreservation(
        from source: Workspace,
        to destination: Workspace
    ) throws {
        guard source.id == destination.id else {
            throw WorkspaceManifestMigrationError.preservationCheckFailed("workspace identity")
        }
        guard source.assets.map(\.id) == destination.assets.map(\.id),
              source.assets.map(\.relativePath) == destination.assets.map(\.relativePath),
              source.assets.map(\.contentHash) == destination.assets.map(\.contentHash) else {
            throw WorkspaceManifestMigrationError.preservationCheckFailed("asset identity or path")
        }
        guard source.canvasNodes == destination.canvasNodes else {
            throw WorkspaceManifestMigrationError.preservationCheckFailed("canvas placements")
        }
        guard source.promptModules.map(\.id) == destination.promptModules.map(\.id),
              source.textBlocks.map(\.id) == destination.textBlocks.map(\.id),
              source.recipes.map(\.id) == destination.recipes.map(\.id),
              source.generators.map(\.id) == destination.generators.map(\.id),
              source.compiledPrompts.map(\.id) == destination.compiledPrompts.map(\.id),
              source.generations.map(\.id) == destination.generations.map(\.id),
              source.generationGroups.map(\.id) == destination.generationGroups.map(\.id),
              source.jobs.map(\.id) == destination.jobs.map(\.id) else {
            throw WorkspaceManifestMigrationError.preservationCheckFailed("entity collections")
        }
    }
}
