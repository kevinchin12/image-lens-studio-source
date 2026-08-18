import Foundation
import XCTest
@testable import ImageLensCore

final class PromptCompilerTests: XCTestCase {
    func testGenerationCompilationPlacesSubjectsBeforeAuthoredPromptAndOthersAfter() {
        let subject = module(.visual(.subject), "红色跑车")
        let style = module(.visual(.style), "电影感")
        let lighting = module(.visual(.lighting), "清晨侧光")
        let environment = module(.visual(.environment), "海边公路")
        let recipe = Recipe(
            name: "Generation Composition",
            bindings: [
                binding(environment, order: 0),
                binding(subject, order: 99),
                binding(lighting, order: 2),
                binding(style, order: 1)
            ],
            target: target
        )
        let authored = PromptOverride(text: "保持车身标志不变\n驶向远处")

        let result = PromptCompiler().compileGeneration(
            recipe: recipe,
            modules: [lighting, environment, style, subject],
            authoredPrompt: authored
        )

        XCTAssertEqual(
            result.finalText,
            "红色跑车; 保持车身标志不变\n驶向远处; 电影感; 清晨侧光; 海边公路"
        )
        XCTAssertEqual(result.override, authored)
        XCTAssertEqual(result.sourceModuleIDs, [subject.id, style.id, lighting.id, environment.id])
    }

    func testGenerationCompilationLeavesAuthoredPromptIndependentOfBindings() {
        let subject = module(.visual(.subject), "人物主体")
        let style = module(.visual(.style), "水彩")
        let recipe = Recipe(
            name: "Lossless Disconnect",
            bindings: [binding(subject, order: 0), binding(style, order: 1)],
            target: target
        )
        let authored = PromptOverride(text: "原始手写提示词；内部标点保持。")

        let connected = PromptCompiler().compileGeneration(
            recipe: recipe,
            modules: [subject, style],
            authoredPrompt: authored
        )
        let disconnected = PromptCompiler().compileGeneration(
            recipe: Recipe(name: recipe.name, target: target),
            modules: [subject, style],
            authoredPrompt: authored
        )

        XCTAssertEqual(connected.finalText, "人物主体; 原始手写提示词；内部标点保持。; 水彩")
        XCTAssertEqual(disconnected.finalText, authored.text)
        XCTAssertEqual(disconnected.override?.text, authored.text)
        XCTAssertNotEqual(connected.inputFingerprint, disconnected.inputFingerprint)
    }

    func testGenerationCompilationSupportsModuleOnlyPrompt() {
        let subject = module(.visual(.subject), "一只白猫")
        let composition = module(.visual(.composition), "居中构图")
        let recipe = Recipe(
            name: "Module Only",
            bindings: [binding(composition, order: 0), binding(subject, order: 1)],
            target: target
        )

        let result = PromptCompiler().compileGeneration(
            recipe: recipe,
            modules: [composition, subject],
            authoredPrompt: nil
        )

        XCTAssertEqual(result.finalText, "一只白猫; 居中构图")
        XCTAssertNil(result.override)
    }

    func testGenerationCompilationPreservesAuthoredPromptBody() {
        let subject = module(.visual(.subject), "主体补充")
        let style = module(.visual(.style), "风格补充")
        let authored = PromptOverride(text: "  第一行\n第二行；保持标点。  ")
        let recipe = Recipe(
            name: "Authored Body",
            bindings: [binding(style, order: 0), binding(subject, order: 1)],
            target: target
        )

        let result = PromptCompiler().compileGeneration(
            recipe: recipe,
            modules: [style, subject],
            authoredPrompt: authored
        )

        XCTAssertEqual(result.finalText, "主体补充; 第一行\n第二行；保持标点。; 风格补充")
        XCTAssertEqual(result.override?.text, authored.text)
    }

    func testGeneratorDisplayUsesModuleLineBreaksWithoutChangingCompiledPrompt() {
        let subject = module(.visual(.subject), "木质书桌，摆放文件夹。")
        let environment = module(.visual(.environment), "温馨室内，靠近薄纱窗帘。")
        let recipe = Recipe(
            name: "Readable Preview",
            bindings: [binding(subject, order: 0), binding(environment, order: 1)],
            target: target
        )

        let result = PromptCompiler().compile(
            recipe: recipe,
            modules: [environment, subject]
        )

        XCTAssertEqual(result.finalText, "木质书桌，摆放文件夹。; 温馨室内，靠近薄纱窗帘。")
        XCTAssertEqual(
            PromptDisplayFormatter.generatorNodeText(for: result),
            "木质书桌，摆放文件夹。\n温馨室内，靠近薄纱窗帘。"
        )
    }

    func testGeneratorDisplayPreservesUserOverridePunctuation() {
        let subject = module(.visual(.subject), "ignored module")
        let override = PromptOverride(text: "保留红色；蓝色只用于点缀。")
        let recipe = Recipe(
            name: "Override",
            bindings: [binding(subject, order: 0)],
            target: target,
            promptOverride: override
        )

        let result = PromptCompiler().compile(recipe: recipe, modules: [subject])

        XCTAssertEqual(
            PromptDisplayFormatter.generatorNodeText(for: result),
            "保留红色；蓝色只用于点缀。"
        )
    }

    func testLegacyGeneratorDisplayOnlyReplacesSeparatorAfterSentenceEnding() {
        let snapshot = CompiledPromptSnapshot(
            recipeID: RecipeID(),
            target: target,
            baseText: "",
            finalText: "红色；蓝色点缀。; 温馨室内。",
            override: nil,
            sourceModuleIDs: [],
            warnings: []
        )

        XCTAssertEqual(
            PromptDisplayFormatter.generatorNodeText(for: snapshot),
            "红色；蓝色点缀。\n温馨室内。"
        )
    }

    func testCompilerUsesFixedVisualOrderThenExplicitInstructionOrder() {
        let subject = module(.visual(.subject), "armored traveler")
        let style = module(.visual(.style), "editorial science-fiction illustration")
        let lateInstruction = module(.instruction, "avoid text")
        let primaryInstruction = module(.instruction, "keep the silhouette readable")
        let recipe = Recipe(
            name: "Ordered",
            bindings: [
                binding(lateInstruction, order: 90),
                binding(style, order: 0),
                binding(subject, order: 200),
                binding(primaryInstruction, order: 100, priority: .primary)
            ],
            target: target
        )

        let result = PromptCompiler().compile(
            recipe: recipe,
            modules: [lateInstruction, style, primaryInstruction, subject]
        )

        XCTAssertEqual(
            result.baseText,
            "armored traveler; editorial science-fiction illustration; "
                + "keep the silhouette readable; avoid text"
        )
        XCTAssertEqual(
            result.moduleInputs.map(\.moduleID),
            [subject.id, style.id, primaryInstruction.id, lateInstruction.id]
        )
        XCTAssertFalse(result.warnings.contains(.missingCategory(.lighting)))
    }

    func testCompilerHonorsBindingAndModuleEnabledStateAndPrimaryPriority() {
        let primary = module(.visual(.style), "ink drawing")
        let supporting = module(.visual(.style), "rough paper grain")
        let disabledByBinding = module(.visual(.style), "neon gradient")
        let disabledModule = module(.visual(.style), "oil paint", isEnabled: false)
        let recipe = Recipe(
            name: "Enabled",
            bindings: [
                binding(supporting, order: 0),
                binding(primary, order: 99, priority: .primary),
                binding(disabledByBinding, order: 1, isEnabled: false),
                binding(disabledModule, order: 2)
            ],
            target: target
        )

        let result = PromptCompiler().compile(
            recipe: recipe,
            modules: [supporting, primary, disabledByBinding, disabledModule]
        )

        XCTAssertEqual(result.baseText, "ink drawing; rough paper grain")
        XCTAssertEqual(result.moduleInputs.map(\.moduleID), [primary.id, supporting.id])
        XCTAssertTrue(result.warnings.contains(.multipleModules(category: .style, count: 2)))
    }

    func testCompilerSkipsBlankAndMismatchedInputsWithWarnings() {
        let blank = module(.visual(.subject), " \n ")
        let mismatched = module(.visual(.lighting), "rim light")
        let missingID = PromptModuleID()
        let recipe = Recipe(
            name: "Invalid",
            bindings: [
                binding(blank, order: 0),
                RecipeInputBinding(
                    moduleID: mismatched.id,
                    role: .visual(.style),
                    order: 1
                ),
                RecipeInputBinding(
                    moduleID: missingID,
                    role: .instruction,
                    order: 2
                )
            ],
            target: target
        )

        let result = PromptCompiler().compile(recipe: recipe, modules: [blank, mismatched])

        XCTAssertEqual(result.baseText, "")
        XCTAssertTrue(result.warnings.contains(.emptyModule(blank.id)))
        XCTAssertTrue(result.warnings.contains(.roleMismatch(moduleID: mismatched.id)))
        XCTAssertTrue(result.warnings.contains(.missingModule(missingID)))
        XCTAssertTrue(result.warnings.contains(.missingCategory(.subject)))
        XCTAssertTrue(result.warnings.contains(.missingCategory(.style)))
    }

    func testCompilerDeduplicatesVisualTextAndWarnsForSameCategory() {
        let first = module(.visual(.style), "soft watercolor")
        let second = module(.visual(.style), "SOFT WATERCOLOR")
        let recipe = Recipe(
            name: "Duplicate",
            bindings: [binding(first, order: 0), binding(second, order: 1)],
            target: target
        )

        let result = PromptCompiler().compile(recipe: recipe, modules: [first, second])

        XCTAssertEqual(result.baseText, "soft watercolor")
        XCTAssertEqual(result.moduleInputs.map(\.moduleID), [first.id])
        XCTAssertTrue(result.warnings.contains(.multipleModules(category: .style, count: 2)))
        XCTAssertTrue(result.warnings.contains(.duplicateText(category: .style)))
    }

    func testSnapshotFreezesInputsAndRecipeMetadataWithoutMutatingRecipe() {
        let assetID = AssetID()
        let analysisID = AnalysisSnapshotID()
        let subject = module(
            .visual(.subject),
            "red ceramic cup",
            evidence: .inferred,
            revision: 7,
            sourceAssetID: assetID,
            sourceAnalysisSnapshotID: analysisID
        )
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshotID = CompiledPromptID()
        let override = PromptOverride(
            text: "custom final request",
            updatedAt: Date(timeIntervalSince1970: 9)
        )
        let recipe = Recipe(
            name: "Snapshot",
            bindings: [binding(subject, order: 0, priority: .primary)],
            target: target,
            promptOverride: override,
            revision: 12,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let originalRecipe = recipe

        let result = PromptCompiler().compile(
            recipe: recipe,
            modules: [subject],
            snapshotID: snapshotID,
            timestamp: timestamp
        )

        XCTAssertEqual(recipe, originalRecipe)
        XCTAssertEqual(result.id, snapshotID)
        XCTAssertEqual(result.recipeRevision, 12)
        XCTAssertEqual(result.compilerVersion, PromptCompiler.version)
        XCTAssertEqual(result.baseText, "red ceramic cup")
        XCTAssertEqual(result.finalText, "custom final request")
        XCTAssertEqual(result.override, override)
        XCTAssertEqual(
            result.moduleInputs,
            [
                ModuleInputSnapshot(
                    moduleID: subject.id,
                    revision: 7,
                    role: .visual(.subject),
                    resolvedContent: "red ceramic cup",
                    evidence: .inferred,
                    sourceAssetID: assetID,
                    sourceAnalysisSnapshotID: analysisID
                )
            ]
        )
        XCTAssertEqual(result.sourceModuleIDs, [subject.id])
        XCTAssertTrue(result.inputFingerprint.hasPrefix("fnv1a64:"))
    }

    func testFingerprintIsStableButChangesWithCompiledInput() {
        let id = PromptModuleID(UUID(uuidString: "10000000-0000-0000-0000-000000000001")!)
        let bindingID = RecipeBindingID(UUID(uuidString: "20000000-0000-0000-0000-000000000002")!)
        let recipeID = RecipeID(UUID(uuidString: "30000000-0000-0000-0000-000000000003")!)
        let first = PromptModule(
            id: id,
            role: .visual(.subject),
            content: "glass whale",
            evidence: .observable,
            revision: 2
        )
        let recipe = Recipe(
            id: recipeID,
            name: "Fingerprint",
            bindings: [
                RecipeInputBinding(
                    id: bindingID,
                    moduleID: id,
                    role: .visual(.subject),
                    order: 0,
                    priority: .primary
                )
            ],
            target: target,
            revision: 4
        )
        let compiler = PromptCompiler()

        let a = compiler.compile(recipe: recipe, modules: [first])
        let b = compiler.compile(recipe: recipe, modules: [first])
        var changed = first
        changed.content = "paper whale"
        changed.revision += 1
        let c = compiler.compile(recipe: recipe, modules: [changed])

        XCTAssertEqual(a.inputFingerprint, b.inputFingerprint)
        XCTAssertNotEqual(a.inputFingerprint, c.inputFingerprint)
    }

    func testLegacySlotInitializerStillCompiles() {
        let subject = module(.visual(.subject), "paper bird")
        let recipe = Recipe(
            name: "Legacy",
            slots: [RecipeSlot(category: .subject, moduleIDs: [subject.id])],
            target: target
        )

        let result = PromptCompiler().compile(recipe: recipe, modules: [subject])

        XCTAssertEqual(result.baseText, "paper bird")
        XCTAssertEqual(result.sourceModuleIDs, [subject.id])
    }

    private let target = CompileTarget(providerID: "test", modelID: "model")

    private func binding(
        _ module: PromptModule,
        order: Int,
        priority: RecipeBindingPriority = .supporting,
        isEnabled: Bool = true
    ) -> RecipeInputBinding {
        RecipeInputBinding(
            moduleID: module.id,
            role: module.role,
            order: order,
            priority: priority,
            isEnabled: isEnabled
        )
    }

    private func module(
        _ role: PromptModuleRole,
        _ content: String,
        evidence: PromptEvidence = .observable,
        revision: Int = 0,
        sourceAssetID: AssetID? = nil,
        sourceAnalysisSnapshotID: AnalysisSnapshotID? = nil,
        isEnabled: Bool = true
    ) -> PromptModule {
        PromptModule(
            role: role,
            content: content,
            sourceAssetID: sourceAssetID,
            sourceAnalysisSnapshotID: sourceAnalysisSnapshotID,
            evidence: evidence,
            isEnabled: isEnabled,
            revision: revision
        )
    }
}
