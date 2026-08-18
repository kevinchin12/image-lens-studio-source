import Foundation
import XCTest
@testable import ImageLensCore

final class NodeGrammarModelTests: XCTestCase {
    private let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    func testInstructionPromptModuleRoundTrips() throws {
        let module = PromptModule(
            id: PromptModuleID(uuid("10000000-0000-0000-0000-000000000001")),
            role: .instruction,
            content: "Keep the logo legible and preserve its proportions.",
            sourceAssetID: AssetID(uuid("10000000-0000-0000-0000-000000000002")),
            evidence: .userProvided,
            evidenceClaims: [
                PromptEvidenceClaim(kind: .userProvided, statement: "The logo must not be redrawn.")
            ],
            isEnabled: true,
            isLocked: true,
            revision: 3,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        let decoded = try roundTrip(module)

        XCTAssertEqual(decoded, module)
        XCTAssertEqual(decoded.role, .instruction)
        XCTAssertNil(decoded.category)
    }

    func testLegacyPromptModuleCategoryJSONDecodesAsVisualRole() throws {
        let moduleID = PromptModuleID(uuid("20000000-0000-0000-0000-000000000001"))
        let payload = LegacyPromptModulePayload(
            id: moduleID,
            category: .style,
            content: "editorial cut-paper collage",
            evidence: .observable,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        let decoded = try decode(PromptModule.self, from: payload)

        XCTAssertEqual(decoded.id, moduleID)
        XCTAssertEqual(decoded.role, .visual(.style))
        XCTAssertEqual(decoded.category, .style)
        XCTAssertEqual(decoded.evidenceClaims, [])
        XCTAssertTrue(decoded.isEnabled)
        XCTAssertFalse(decoded.isLocked)
        XCTAssertEqual(decoded.revision, 0)
    }

    func testRecipeBindingsRoundTrip() throws {
        let visualModuleID = PromptModuleID(uuid("30000000-0000-0000-0000-000000000001"))
        let instructionModuleID = PromptModuleID(uuid("30000000-0000-0000-0000-000000000002"))
        let recipe = Recipe(
            id: RecipeID(uuid("30000000-0000-0000-0000-000000000003")),
            name: "Campaign key visual",
            bindings: [
                RecipeInputBinding(
                    id: RecipeBindingID(uuid("30000000-0000-0000-0000-000000000004")),
                    moduleID: visualModuleID,
                    role: .visual(.subject),
                    order: 0,
                    priority: .primary
                ),
                RecipeInputBinding(
                    id: RecipeBindingID(uuid("30000000-0000-0000-0000-000000000005")),
                    moduleID: instructionModuleID,
                    role: .instruction,
                    order: 1,
                    priority: .supporting
                )
            ],
            target: CompileTarget(providerID: "openai", modelID: "image-model", languageCode: "en"),
            promptOverride: PromptOverride(text: "Use the approved final copy.", updatedAt: timestamp),
            revision: 4,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        let decoded = try roundTrip(recipe)

        XCTAssertEqual(decoded, recipe)
        XCTAssertEqual(decoded.bindings.map(\.role), [.visual(.subject), .instruction])
        XCTAssertEqual(decoded.bindings.map(\.priority), [.primary, .supporting])
    }

    func testLegacyRecipeSlotsJSONDecodesAsBindings() throws {
        let supportingModuleID = PromptModuleID(uuid("40000000-0000-0000-0000-000000000001"))
        let primaryModuleID = PromptModuleID(uuid("40000000-0000-0000-0000-000000000002"))
        let payload = LegacyRecipePayload(
            id: RecipeID(uuid("40000000-0000-0000-0000-000000000003")),
            name: "Legacy recipe",
            slots: [
                RecipeSlot(
                    category: .style,
                    moduleIDs: [supportingModuleID, primaryModuleID],
                    primaryModuleID: primaryModuleID,
                    isEnabled: true
                )
            ],
            target: CompileTarget(providerID: "legacy", modelID: "legacy-model"),
            createdAt: timestamp,
            updatedAt: timestamp
        )

        let decoded = try decode(Recipe.self, from: payload)

        XCTAssertEqual(decoded.revision, 0)
        XCTAssertEqual(decoded.bindings.map(\.moduleID), [supportingModuleID, primaryModuleID])
        XCTAssertEqual(decoded.bindings.map(\.role), [.visual(.style), .visual(.style)])
        XCTAssertEqual(decoded.bindings.map(\.order), [0, 1])
        XCTAssertEqual(decoded.bindings.map(\.priority), [.supporting, .primary])
        XCTAssertTrue(decoded.bindings.allSatisfy(\.isEnabled))
    }

    func testGeneratorConfigurationAndGenerationAttemptsRemainSeparate() throws {
        let recipeID = RecipeID(uuid("50000000-0000-0000-0000-000000000001"))
        let generator = Generator(
            id: GeneratorID(uuid("50000000-0000-0000-0000-000000000002")),
            name: "Square product generator",
            recipeID: recipeID,
            target: CompileTarget(providerID: "openai", modelID: "image-model"),
            parameters: GenerationParameters(
                aspectRatio: "1:1",
                seed: 42,
                variationCount: 2,
                providerOptions: ["quality": "high"]
            ),
            assetBindings: [
                GeneratorAssetBinding(
                    id: GeneratorAssetBindingID(uuid("50000000-0000-0000-0000-000000000003")),
                    assetID: AssetID(uuid("50000000-0000-0000-0000-000000000004")),
                    role: .identity,
                    order: 0
                )
            ],
            revision: 2,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let firstAttempt = GenerationRecord(
            id: GenerationID(uuid("50000000-0000-0000-0000-000000000005")),
            generatorID: generator.id,
            recipeID: recipeID,
            promptSnapshotID: CompiledPromptID(uuid("50000000-0000-0000-0000-000000000006")),
            providerID: "openai",
            modelID: "image-model",
            aspectRatio: "1:1",
            state: .failed,
            createdAt: timestamp
        )
        let retryAttempt = GenerationRecord(
            id: GenerationID(uuid("50000000-0000-0000-0000-000000000007")),
            generatorID: generator.id,
            retryOfGenerationID: firstAttempt.id,
            recipeID: recipeID,
            promptSnapshotID: CompiledPromptID(uuid("50000000-0000-0000-0000-000000000008")),
            providerID: "openai",
            modelID: "image-model",
            aspectRatio: "1:1",
            state: .queued,
            createdAt: timestamp
        )

        XCTAssertEqual(try roundTrip(generator), generator)
        XCTAssertEqual(try roundTrip(firstAttempt), firstAttempt)
        XCTAssertEqual(try roundTrip(retryAttempt), retryAttempt)
        XCTAssertEqual(firstAttempt.generatorID, generator.id)
        XCTAssertEqual(retryAttempt.generatorID, generator.id)
        XCTAssertEqual(retryAttempt.retryOfGenerationID, firstAttempt.id)
        XCTAssertEqual(generator.recipeID, firstAttempt.recipeID)
        XCTAssertEqual(generator.revision, 2)
        XCTAssertEqual(firstAttempt.state, .failed)
        XCTAssertEqual(retryAttempt.state, .queued)
    }

    func testLegacyWorkspaceManifestWithoutGeneratorsDecodesWithEmptyCollection() throws {
        let workspaceID = WorkspaceID(uuid("60000000-0000-0000-0000-000000000001"))
        let payload = LegacyWorkspaceManifest(
            schemaVersion: 1,
            id: workspaceID,
            title: "Legacy workspace",
            assets: [],
            analysisSnapshots: [],
            promptModules: [],
            recipes: [],
            compiledPrompts: [],
            generations: [],
            jobs: [],
            canvasNodes: [],
            createdAt: timestamp,
            updatedAt: timestamp
        )

        let decoded = try decode(Workspace.self, from: payload)

        XCTAssertEqual(decoded.id, workspaceID)
        XCTAssertEqual(decoded.title, "Legacy workspace")
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertTrue(decoded.generators.isEmpty)
    }

    private func roundTrip<Value: Codable>(_ value: Value) throws -> Value {
        let data = try encoder().encode(value)
        return try decoder().decode(Value.self, from: data)
    }

    private func decode<Value: Decodable, Payload: Encodable>(
        _ type: Value.Type,
        from payload: Payload
    ) throws -> Value {
        let data = try encoder().encode(payload)
        return try decoder().decode(type, from: data)
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func uuid(_ value: String) -> UUID {
        guard let uuid = UUID(uuidString: value) else {
            preconditionFailure("Invalid test UUID: \(value)")
        }
        return uuid
    }
}

private struct LegacyPromptModulePayload: Encodable {
    let id: PromptModuleID
    let category: PromptModuleCategory
    let content: String
    let evidence: PromptEvidence
    let createdAt: Date
    let updatedAt: Date
}

private struct LegacyRecipePayload: Encodable {
    let id: RecipeID
    let name: String
    let slots: [RecipeSlot]
    let target: CompileTarget
    let createdAt: Date
    let updatedAt: Date
}

private struct LegacyWorkspaceManifest: Encodable {
    let schemaVersion: Int
    let id: WorkspaceID
    let title: String
    let assets: [Asset]
    let analysisSnapshots: [AnalysisSnapshot]
    let promptModules: [PromptModule]
    let recipes: [Recipe]
    let compiledPrompts: [CompiledPromptSnapshot]
    let generations: [GenerationRecord]
    let jobs: [JobRecord]
    let canvasNodes: [CanvasNode]
    let createdAt: Date
    let updatedAt: Date
}
