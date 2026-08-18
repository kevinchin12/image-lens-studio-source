import Foundation

/// Deterministically turns a recipe's enabled bindings into an immutable prompt snapshot.
///
/// Visual modules always use `PromptModuleCategory.allCases` order. Instructions follow
/// the visual prompt and retain their explicit recipe order. No model call or implicit
/// rewrite is performed during compilation.
public struct PromptCompiler: Sendable {
    public static let version = "1.1.0"

    public init() {}

    /// Compiles the prompt owned by a generation node without rewriting it.
    ///
    /// Connected structured modules remain canonical recipe bindings. Subject
    /// modules lead the user-authored prompt, while every other structured
    /// module follows it. This keeps the editable text byte-for-byte separate
    /// from optional analysis context and makes disconnecting lossless.
    public func compileGeneration(
        recipe: Recipe,
        modules: [PromptModule],
        authoredPrompt: PromptOverride?,
        snapshotID: CompiledPromptID = CompiledPromptID(),
        timestamp: Date = .now
    ) -> CompiledPromptSnapshot {
        var moduleRecipe = recipe
        moduleRecipe.promptOverride = nil
        let moduleSnapshot = compile(
            recipe: moduleRecipe,
            modules: modules,
            snapshotID: snapshotID,
            timestamp: timestamp
        )

        let subjectFragments = moduleSnapshot.moduleInputs.compactMap { input in
            input.role == .visual(.subject) ? input.resolvedContent : nil
        }
        let trailingFragments = moduleSnapshot.moduleInputs.compactMap { input in
            input.role == .visual(.subject) ? nil : input.resolvedContent
        }
        let rawAuthoredText = authoredPrompt?.text ?? ""
        let authoredText = rawAuthoredText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let finalText = (
            subjectFragments
                + (authoredText.isEmpty ? [] : [authoredText])
                + trailingFragments
        ).joined(separator: "; ")

        var fingerprintRecipe = moduleRecipe
        fingerprintRecipe.promptOverride = authoredText.isEmpty ? nil : authoredPrompt
        let fingerprint = inputFingerprint(
            recipe: fingerprintRecipe,
            modulesByID: canonicalModuleLookup(modules),
            moduleInputs: moduleSnapshot.moduleInputs,
            baseText: moduleSnapshot.baseText,
            finalText: finalText
        )

        return CompiledPromptSnapshot(
            id: snapshotID,
            recipeID: recipe.id,
            recipeRevision: recipe.revision,
            compilerVersion: Self.version,
            target: recipe.target,
            moduleInputs: moduleSnapshot.moduleInputs,
            baseText: moduleSnapshot.baseText,
            finalText: finalText,
            override: authoredText.isEmpty ? nil : authoredPrompt,
            sourceModuleIDs: moduleSnapshot.sourceModuleIDs,
            warnings: moduleSnapshot.warnings,
            inputFingerprint: fingerprint,
            createdAt: timestamp
        )
    }

    public func compile(
        recipe: Recipe,
        modules: [PromptModule],
        snapshotID: CompiledPromptID = CompiledPromptID(),
        timestamp: Date = .now
    ) -> CompiledPromptSnapshot {
        let modulesByID = canonicalModuleLookup(modules)
        let activeBindings = recipe.bindings.enumerated().filter { $0.element.isEnabled }
        var warnings: [CompileWarning] = []
        var moduleInputs: [ModuleInputSnapshot] = []
        var fragments: [String] = []

        for category in PromptModuleCategory.allCases {
            let bindings = sortedBindings(
                activeBindings.filter { $0.element.role == .visual(category) }
            )
            // Recipes are intentionally partial: an omitted visual category means
            // "do not use this aspect", not an incomplete prompt.
            guard !bindings.isEmpty else { continue }
            let inputs = resolve(
                bindings: bindings,
                modulesByID: modulesByID,
                expectedRole: .visual(category),
                warnings: &warnings
            )

            guard !inputs.isEmpty else {
                warnings.append(.missingCategory(category))
                continue
            }
            if inputs.count > 1 {
                warnings.append(.multipleModules(category: category, count: inputs.count))
            }

            appendDeduplicated(
                inputs,
                duplicateWarning: .duplicateText(category: category),
                to: &moduleInputs,
                fragments: &fragments,
                warnings: &warnings
            )
        }

        let instructionBindings = sortedBindings(
            activeBindings.filter { $0.element.role == .instruction }
        )
        let instructionInputs = resolve(
            bindings: instructionBindings,
            modulesByID: modulesByID,
            expectedRole: .instruction,
            warnings: &warnings
        )
        appendDeduplicated(
            instructionInputs,
            duplicateWarning: nil,
            to: &moduleInputs,
            fragments: &fragments,
            warnings: &warnings
        )

        let baseText = fragments.joined(separator: "; ")
        let overrideText = recipe.promptOverride?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalText = overrideText.flatMap { $0.isEmpty ? nil : $0 } ?? baseText
        let fingerprint = inputFingerprint(
            recipe: recipe,
            modulesByID: modulesByID,
            moduleInputs: moduleInputs,
            baseText: baseText,
            finalText: finalText
        )

        return CompiledPromptSnapshot(
            id: snapshotID,
            recipeID: recipe.id,
            recipeRevision: recipe.revision,
            compilerVersion: Self.version,
            target: recipe.target,
            moduleInputs: moduleInputs,
            baseText: baseText,
            finalText: finalText,
            override: recipe.promptOverride,
            sourceModuleIDs: moduleInputs.map(\.moduleID),
            warnings: warnings,
            inputFingerprint: fingerprint,
            createdAt: timestamp
        )
    }

    private typealias IndexedBinding = (offset: Int, element: RecipeInputBinding)

    private func canonicalModuleLookup(
        _ modules: [PromptModule]
    ) -> [PromptModuleID: PromptModule] {
        var result: [PromptModuleID: PromptModule] = [:]
        for module in modules {
            guard let existing = result[module.id] else {
                result[module.id] = module
                continue
            }

            // Duplicate entity IDs are invalid, but choosing canonically keeps compilation
            // stable even when an imported manifest contains duplicate records.
            if module.revision > existing.revision
                || (module.revision == existing.revision && module.content < existing.content) {
                result[module.id] = module
            }
        }
        return result
    }

    private func sortedBindings(_ bindings: [IndexedBinding]) -> [IndexedBinding] {
        bindings.sorted { lhs, rhs in
            if lhs.element.priority != rhs.element.priority {
                return lhs.element.priority == .primary
            }
            if lhs.element.order != rhs.element.order {
                return lhs.element.order < rhs.element.order
            }
            if lhs.offset != rhs.offset {
                return lhs.offset < rhs.offset
            }
            return lhs.element.id.rawValue.uuidString < rhs.element.id.rawValue.uuidString
        }
    }

    private func resolve(
        bindings: [IndexedBinding],
        modulesByID: [PromptModuleID: PromptModule],
        expectedRole: PromptModuleRole,
        warnings: inout [CompileWarning]
    ) -> [ModuleInputSnapshot] {
        bindings.compactMap { indexedBinding in
            let binding = indexedBinding.element
            guard let module = modulesByID[binding.moduleID] else {
                warnings.append(.missingModule(binding.moduleID))
                return nil
            }
            guard module.isEnabled else { return nil }
            guard module.role == expectedRole else {
                warnings.append(.roleMismatch(moduleID: module.id))
                return nil
            }

            let content = module.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else {
                warnings.append(.emptyModule(module.id))
                return nil
            }

            return ModuleInputSnapshot(
                moduleID: module.id,
                revision: module.revision,
                role: module.role,
                resolvedContent: content,
                evidence: module.evidence,
                sourceAssetID: module.sourceAssetID,
                sourceAnalysisSnapshotID: module.sourceAnalysisSnapshotID
            )
        }
    }

    private func appendDeduplicated(
        _ inputs: [ModuleInputSnapshot],
        duplicateWarning: CompileWarning?,
        to moduleInputs: inout [ModuleInputSnapshot],
        fragments: inout [String],
        warnings: inout [CompileWarning]
    ) {
        var normalizedText = Set<String>()
        for input in inputs {
            let normalized = input.resolvedContent.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            guard normalizedText.insert(normalized).inserted else {
                if let duplicateWarning {
                    warnings.append(duplicateWarning)
                }
                continue
            }
            moduleInputs.append(input)
            fragments.append(input.resolvedContent)
        }
    }

    private func inputFingerprint(
        recipe: Recipe,
        modulesByID: [PromptModuleID: PromptModule],
        moduleInputs: [ModuleInputSnapshot],
        baseText: String,
        finalText: String
    ) -> String {
        var fields = [
            Self.version,
            recipe.id.rawValue.uuidString.lowercased(),
            String(recipe.revision),
            recipe.target.providerID.rawValue,
            recipe.target.modelID,
            recipe.target.languageCode
        ]

        // Bindings are part of the recipe input, including disabled or unresolved ones.
        // Their declaration order is captured as a final deterministic tie-breaker.
        for (offset, binding) in recipe.bindings.enumerated() {
            fields.append(contentsOf: [
                "binding",
                String(offset),
                binding.id.rawValue.uuidString.lowercased(),
                binding.moduleID.rawValue.uuidString.lowercased(),
                stableRole(binding.role),
                String(binding.order),
                binding.priority.rawValue,
                String(binding.isEnabled)
            ])
            if let module = modulesByID[binding.moduleID] {
                fields.append(contentsOf: [
                    String(module.revision),
                    module.content,
                    module.evidence.rawValue,
                    module.sourceAssetID?.rawValue.uuidString.lowercased() ?? "-",
                    module.sourceAnalysisSnapshotID?.rawValue.uuidString.lowercased() ?? "-",
                    String(module.isEnabled)
                ])
            } else {
                fields.append("missing")
            }
        }

        for input in moduleInputs {
            fields.append(contentsOf: [
                "resolved",
                input.moduleID.rawValue.uuidString.lowercased(),
                String(input.revision),
                stableRole(input.role),
                input.resolvedContent,
                input.evidence.rawValue,
                input.sourceAssetID?.rawValue.uuidString.lowercased() ?? "-",
                input.sourceAnalysisSnapshotID?.rawValue.uuidString.lowercased() ?? "-"
            ])
        }
        fields.append(contentsOf: [
            "base", baseText,
            "override", recipe.promptOverride?.text ?? "-",
            "final", finalText
        ])

        // FNV-1a is used as a stable change fingerprint, not as a security primitive.
        var hash: UInt64 = 0xcbf29ce484222325
        for field in fields {
            let bytes = Array(field.utf8)
            for byte in withUnsafeBytes(of: UInt64(bytes.count).littleEndian, Array.init) + bytes {
                hash ^= UInt64(byte)
                hash = hash &* 0x100000001b3
            }
        }
        return "fnv1a64:" + String(hash, radix: 16, uppercase: false)
    }

    private func stableRole(_ role: PromptModuleRole) -> String {
        switch role {
        case .visual(let category):
            "visual:\(category.rawValue)"
        case .instruction:
            "instruction"
        }
    }
}
