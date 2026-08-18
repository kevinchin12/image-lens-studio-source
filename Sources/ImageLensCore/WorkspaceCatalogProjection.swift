import Foundation

/// Read-only projections used by the workspace's material library and
/// generation history.
///
/// These functions intentionally do not mutate or persist collection
/// membership.
public enum WorkspaceCatalogProjection {
    /// Returns the assets that belong in the user-facing material library.
    ///
    /// Source assets default to saved in the model because importing them is an
    /// explicit act. Generated assets default to history-only. Input order is
    /// preserved so callers remain in control of presentation sorting.
    public static func libraryAssets(
        from assets: some Sequence<Asset>
    ) -> [Asset] {
        assets.filter(\.isSavedToLibrary)
    }

    public static func isLibraryAsset(_ asset: Asset) -> Bool {
        asset.isSavedToLibrary
    }

    /// Builds newest-first history rows while assigning same-topic ordinals in
    /// chronological order.
    ///
    /// Ordinals do not depend on the input collection's order. A generator ID
    /// is the preferred topic identity; historical records whose generator no
    /// longer exists still retain that ID and therefore stay grouped. Legacy
    /// records without a generator fall back to their recipe ID.
    public static func generationHistory(
        records: some Sequence<GenerationRecord>,
        generators: some Sequence<Generator>,
        compiledPrompts: some Sequence<CompiledPromptSnapshot>,
        recipes: some Sequence<Recipe>
    ) -> [GenerationHistoryItem] {
        let generatorByID = Dictionary(uniqueKeysWithValues: generators.map { ($0.id, $0) })
        let promptByID = Dictionary(uniqueKeysWithValues: compiledPrompts.map { ($0.id, $0) })
        let recipeByID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })

        let chronological = records.sorted(by: generationAscending)
        let topicCounts = Dictionary(grouping: chronological, by: topicKey(for:))
            .mapValues(\.count)
        var nextOrdinalByTopic: [GenerationTopicKey: Int] = [:]

        let items = chronological.map { record in
            let topicKey = topicKey(for: record)
            let ordinal = (nextOrdinalByTopic[topicKey] ?? 0) + 1
            nextOrdinalByTopic[topicKey] = ordinal

            let topicCount = topicCounts[topicKey] ?? 1
            let persistedDisplayTitle = normalizedPersistedTitle(record.displayTitle)
            let baseTitle: String
            let displayTitle: String

            if let persistedDisplayTitle {
                baseTitle = strippingOrdinal(from: persistedDisplayTitle)
                displayTitle = persistedDisplayTitle == baseTitle && topicCount > 1
                    ? "\(baseTitle) · 第 \(ordinal) 次"
                    : persistedDisplayTitle
            } else {
                let generator = record.generatorID.flatMap { generatorByID[$0] }
                let generatorName = preferredGeneratorName(
                    snapshot: record.generatorNameSnapshot,
                    current: generator?.name
                )
                let prompt = promptByID[record.promptSnapshotID]
                let recipe = recipeByID[record.recipeID]
                baseTitle = GenerationHistoryTitlePolicy.baseTitle(
                    generatorName: generatorName,
                    compiledPrompt: prompt,
                    recipe: recipe
                )
                displayTitle = topicCount > 1
                    ? "\(baseTitle) · 第 \(ordinal) 次"
                    : baseTitle
            }

            return GenerationHistoryItem(
                generation: record,
                baseTitle: baseTitle,
                displayTitle: displayTitle,
                topicKey: topicKey,
                topicOrdinal: ordinal,
                topicCount: topicCount
            )
        }

        return items.reversed()
    }

    private static func topicKey(for record: GenerationRecord) -> GenerationTopicKey {
        if let generatorID = record.generatorID {
            return .generator(generatorID)
        }
        return .recipe(record.recipeID)
    }

    private static func preferredGeneratorName(
        snapshot: String?,
        current: String?
    ) -> String? {
        if let snapshot, isSemanticGeneratorName(snapshot) {
            return snapshot
        }
        return current ?? snapshot
    }

    private static func isSemanticGeneratorName(_ name: String) -> Bool {
        let normalized = WorkspaceDisplayNamePolicy.normalized(name)
        return !normalized.isEmpty
            && normalized != WorkspaceDisplayNameKind.generator.rawValue
            && !WorkspaceDisplayNamePolicy.isDefaultName(normalized, for: .generator)
    }

    private static func normalizedPersistedTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let normalized = WorkspaceDisplayNamePolicy.normalized(title)
        return normalized.isEmpty ? nil : normalized
    }

    private static func strippingOrdinal(from title: String) -> String {
        title.replacingOccurrences(
            of: #"\s*·\s*第\s*\d+\s*次$"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func generationAscending(
        _ lhs: GenerationRecord,
        _ rhs: GenerationRecord
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
    }
}

public enum GenerationTopicKey: Hashable, Sendable {
    case generator(GeneratorID)
    case recipe(RecipeID)
}

public struct GenerationHistoryItem: Identifiable, Equatable, Sendable {
    public var id: GenerationID { generation.id }
    public let generation: GenerationRecord
    public let baseTitle: String
    public let displayTitle: String
    public let topicKey: GenerationTopicKey
    public let topicOrdinal: Int
    public let topicCount: Int

    public init(
        generation: GenerationRecord,
        baseTitle: String,
        displayTitle: String,
        topicKey: GenerationTopicKey,
        topicOrdinal: Int,
        topicCount: Int
    ) {
        self.generation = generation
        self.baseTitle = baseTitle
        self.displayTitle = displayTitle
        self.topicKey = topicKey
        self.topicOrdinal = topicOrdinal
        self.topicCount = topicCount
    }
}

/// Produces compact semantic generation titles without using filenames or
/// timestamps as meaning.
public enum GenerationHistoryTitlePolicy {
    public static let maximumBaseTitleLength = 18

    /// Resolves a title in this order:
    /// custom generator name → structured prompt inputs → final prompt text →
    /// recipe name → a neutral fallback.
    public static func baseTitle(
        generator: Generator?,
        compiledPrompt: CompiledPromptSnapshot?,
        recipe: Recipe?
    ) -> String {
        baseTitle(
            generatorName: generator?.name,
            compiledPrompt: compiledPrompt,
            recipe: recipe
        )
    }

    public static func baseTitle(
        generatorName: String?,
        compiledPrompt: CompiledPromptSnapshot?,
        recipe: Recipe?
    ) -> String {
        if let generatorName,
           isCustomGeneratorName(generatorName) {
            return compactTitle(generatorName)
        }

        if let compiledPrompt {
            let visualInputs = compiledPrompt.moduleInputs
                .filter { $0.role.visualCategory != nil }
                .sorted(by: moduleInputComesFirst)
                .map(\.resolvedContent)
            if let title = semanticTitle(from: visualInputs) {
                return title
            }
            if let title = semanticTitle(from: [compiledPrompt.finalText]) {
                return title
            }
        }

        if let recipe,
           isCustomRecipeName(recipe.name) {
            return compactTitle(recipe.name)
        }

        return "未命名图像创作"
    }

    private static func isCustomGeneratorName(_ name: String) -> Bool {
        let normalized = WorkspaceDisplayNamePolicy.normalized(name)
        return !normalized.isEmpty
            && normalized != WorkspaceDisplayNameKind.generator.rawValue
            && !WorkspaceDisplayNamePolicy.isDefaultName(normalized, for: .generator)
    }

    private static func isCustomRecipeName(_ name: String) -> Bool {
        let normalized = WorkspaceDisplayNamePolicy.normalized(name)
        return !normalized.isEmpty
            && normalized != WorkspaceDisplayNameKind.recipe.rawValue
            && !WorkspaceDisplayNamePolicy.isDefaultName(normalized, for: .recipe)
    }

    private static func moduleInputComesFirst(
        _ lhs: ModuleInputSnapshot,
        _ rhs: ModuleInputSnapshot
    ) -> Bool {
        categoryPriority(lhs.role.visualCategory) < categoryPriority(rhs.role.visualCategory)
    }

    private static func categoryPriority(_ category: PromptModuleCategory?) -> Int {
        switch category {
        case .subject: 0
        case .style: 1
        case .environment: 2
        case .composition: 3
        case .camera: 4
        case .material: 5
        case .lighting: 6
        case .rendering: 7
        case nil: 8
        }
    }

    private static func semanticTitle(from texts: [String]) -> String? {
        var seen = Set<String>()
        let phrases = texts
            .flatMap(semanticPhrases)
            .filter { phrase in
                seen.insert(normalizedTopicText(phrase)).inserted
            }

        guard !phrases.isEmpty else { return nil }

        var title = ""
        for phrase in phrases {
            let separator = title.isEmpty ? "" : " · "
            let remaining = maximumBaseTitleLength - title.count - separator.count
            guard remaining > 0 else { break }

            let clippedPhrase = String(phrase.prefix(remaining))
            guard !clippedPhrase.isEmpty else { continue }
            title += separator + clippedPhrase

            // Twelve characters is long enough to scan as a descriptive title,
            // while shorter source phrases remain unpadded and human-readable.
            if title.count >= 12 { break }
        }

        return title.isEmpty ? nil : title
    }

    private static func semanticPhrases(from text: String) -> [String] {
        normalizedPromptText(text)
            .components(separatedBy: semanticSeparators)
            .map(readablePhrase)
            .filter { !$0.isEmpty }
    }

    private static func readablePhrase(_ phrase: String) -> String {
        var result = phrase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "的", with: "")
        for suffix in genericPromptSuffixes where result.hasSuffix(suffix) {
            result.removeLast(suffix.count)
            break
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func compactTitle(_ text: String) -> String {
        let normalized = normalizedPromptText(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > maximumBaseTitleLength else {
            return normalized
        }
        return String(normalized.prefix(maximumBaseTitleLength - 1)) + "…"
    }

    private static func normalizedPromptText(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedTopicText(_ text: String) -> String {
        normalizedPromptText(text).folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "zh_Hans")
        )
    }

    private static let semanticSeparators = CharacterSet(
        charactersIn: ",，。；;、|｜\n"
    )

    private static let genericPromptSuffixes = [
        "背景",
        "质感",
        "风格",
        "效果",
        "画面",
        "图像",
        "渲染"
    ]
}
