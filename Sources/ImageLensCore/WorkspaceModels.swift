import Foundation

public struct PixelSize: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var aspectRatio: Double? {
        guard width > 0, height > 0 else { return nil }
        return Double(width) / Double(height)
    }
}

public enum AssetKind: String, Codable, CaseIterable, Sendable {
    case source
    case generated
}

/// Immutable provenance for an artifact. This answers where the bytes came
/// from, independently of how the artifact is currently used on the canvas.
public enum AssetProvenance: String, Codable, CaseIterable, Sendable {
    case imported
    case generated
    case derived
    case captured
}

/// Mutable project roles for an artifact. A generated result can later become
/// reusable material without losing its generated provenance.
public enum AssetUsage: String, Codable, CaseIterable, Sendable {
    case material
    case result
    case reference
    case archived
}

/// Media capability derived from the persisted MIME type. Provenance and
/// usage remain independent from the bytes' media format.
public enum AssetMediaKind: String, CaseIterable, Hashable, Sendable {
    case image
    case video
    case unknown
}

public enum AssetState: String, Codable, CaseIterable, Sendable {
    case imported
    case analyzing
    case ready
    case partial
    case failed
}

public struct Asset: Codable, Equatable, Identifiable, Sendable {
    public var id: AssetID
    /// Compatibility identity used by the current canvas implementation.
    /// New code should prefer `provenance` and `usages` when deciding origin
    /// and participation in workflows.
    public var kind: AssetKind
    public var provenance: AssetProvenance
    public var usages: [AssetUsage]
    public var state: AssetState
    /// User intent for the curated material library.
    ///
    /// Source images default to saved because importing them is an explicit
    /// action. Generated images default to history-only and enter the library
    /// only after the user chooses to keep them.
    public var isSavedToLibrary: Bool
    public var displayName: String
    public var relativePath: String
    public var thumbnailRelativePath: String?
    public var mimeType: String
    public var pixelSize: PixelSize?
    public var contentHash: String?
    public var sourceGenerationID: GenerationID?
    public var createdAt: Date

    public init(
        id: AssetID = AssetID(),
        kind: AssetKind,
        provenance: AssetProvenance? = nil,
        usages: [AssetUsage]? = nil,
        state: AssetState = .imported,
        isSavedToLibrary: Bool? = nil,
        displayName: String,
        relativePath: String,
        thumbnailRelativePath: String? = nil,
        mimeType: String,
        pixelSize: PixelSize? = nil,
        contentHash: String? = nil,
        sourceGenerationID: GenerationID? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        let resolvedIsSavedToLibrary = usages?.contains(.material)
            ?? isSavedToLibrary
            ?? (kind == .source)
        self.provenance = provenance ?? Self.defaultProvenance(for: kind)
        self.usages = Self.normalizedUsages(
            usages ?? Self.defaultUsages(
                for: kind,
                isSavedToLibrary: resolvedIsSavedToLibrary
            )
        )
        self.state = state
        self.isSavedToLibrary = resolvedIsSavedToLibrary
        self.displayName = displayName
        self.relativePath = relativePath
        self.thumbnailRelativePath = thumbnailRelativePath
        self.mimeType = mimeType
        self.pixelSize = pixelSize
        self.contentHash = contentHash
        self.sourceGenerationID = sourceGenerationID
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case provenance
        case usages
        case state
        case isSavedToLibrary
        case displayName
        case relativePath
        case thumbnailRelativePath
        case mimeType
        case pixelSize
        case contentHash
        case sourceGenerationID
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(AssetID.self, forKey: .id)
        kind = try container.decode(AssetKind.self, forKey: .kind)
        let legacyIsSavedToLibrary = try container.decodeIfPresent(
            Bool.self,
            forKey: .isSavedToLibrary
        ) ?? (kind == .source)
        provenance = try container.decodeIfPresent(
            AssetProvenance.self,
            forKey: .provenance
        ) ?? Self.defaultProvenance(for: kind)
        let persistedUsages = try container.decodeIfPresent(
            [AssetUsage].self,
            forKey: .usages
        )
        usages = Self.normalizedUsages(
            persistedUsages
                ?? Self.defaultUsages(
                    for: kind,
                    isSavedToLibrary: legacyIsSavedToLibrary
                )
        )
        isSavedToLibrary = persistedUsages == nil
            ? legacyIsSavedToLibrary
            : usages.contains(.material)
        state = try container.decode(AssetState.self, forKey: .state)
        displayName = try container.decode(String.self, forKey: .displayName)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        thumbnailRelativePath = try container.decodeIfPresent(
            String.self,
            forKey: .thumbnailRelativePath
        )
        mimeType = try container.decode(String.self, forKey: .mimeType)
        pixelSize = try container.decodeIfPresent(PixelSize.self, forKey: .pixelSize)
        contentHash = try container.decodeIfPresent(String.self, forKey: .contentHash)
        sourceGenerationID = try container.decodeIfPresent(
            GenerationID.self,
            forKey: .sourceGenerationID
        )
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(provenance, forKey: .provenance)
        try container.encode(usages, forKey: .usages)
        try container.encode(state, forKey: .state)
        try container.encode(usages.contains(.material), forKey: .isSavedToLibrary)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(relativePath, forKey: .relativePath)
        try container.encodeIfPresent(thumbnailRelativePath, forKey: .thumbnailRelativePath)
        try container.encode(mimeType, forKey: .mimeType)
        try container.encodeIfPresent(pixelSize, forKey: .pixelSize)
        try container.encodeIfPresent(contentHash, forKey: .contentHash)
        try container.encodeIfPresent(sourceGenerationID, forKey: .sourceGenerationID)
        try container.encode(createdAt, forKey: .createdAt)
    }

    public var contentAspectRatio: Double? {
        pixelSize?.aspectRatio
    }

    public var mediaKind: AssetMediaKind {
        let normalizedMIMEType = mimeType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalizedMIMEType.hasPrefix("image/") { return .image }
        if normalizedMIMEType.hasPrefix("video/") { return .video }
        return .unknown
    }

    public var isStillImage: Bool { mediaKind == .image }
    public var isVideo: Bool { mediaKind == .video }
    public var isMaterial: Bool { usages.contains(.material) }
    public var isResult: Bool { usages.contains(.result) }
    public var supportsReversePrompt: Bool { isMaterial && isStillImage }
    public var supportsMediaReference: Bool { isStillImage || isVideo }
    /// Compatibility spelling retained while reference workflows migrate from
    /// image-only inputs to generic media inputs.
    public var supportsReferenceBinding: Bool { isStillImage }

    public mutating func addUsage(_ usage: AssetUsage) {
        usages = Self.normalizedUsages(usages + [usage])
        if usage == .material {
            isSavedToLibrary = true
        }
    }

    public mutating func removeUsage(_ usage: AssetUsage) {
        usages.removeAll { $0 == usage }
        if usage == .material {
            isSavedToLibrary = false
        }
    }

    /// Creates a lightweight source-material identity for a generated image.
    ///
    /// The underlying file stays shared with the generated asset. Generation
    /// history therefore keeps its original provenance while the new identity
    /// can participate in source-image analysis and material workflows.
    public func sourceMaterialAlias(
        id: AssetID = AssetID(),
        displayName: String? = nil,
        createdAt: Date = .now
    ) -> Asset {
        Asset(
            id: id,
            kind: .source,
            provenance: provenance,
            usages: [.material],
            state: .imported,
            isSavedToLibrary: true,
            displayName: displayName ?? self.displayName,
            relativePath: relativePath,
            thumbnailRelativePath: thumbnailRelativePath,
            mimeType: mimeType,
            pixelSize: pixelSize,
            contentHash: contentHash,
            sourceGenerationID: sourceGenerationID,
            createdAt: createdAt
        )
    }

    private static func defaultProvenance(for kind: AssetKind) -> AssetProvenance {
        switch kind {
        case .source: .imported
        case .generated: .generated
        }
    }

    private static func defaultUsages(
        for kind: AssetKind,
        isSavedToLibrary: Bool
    ) -> [AssetUsage] {
        switch kind {
        case .source: [.material]
        case .generated:
            isSavedToLibrary ? [.material, .result] : [.result]
        }
    }

    private static func normalizedUsages(_ usages: [AssetUsage]) -> [AssetUsage] {
        AssetUsage.allCases.filter { usages.contains($0) }
    }
}

public enum PromptModuleCategory: String, CaseIterable, Codable, Sendable {
    case subject
    case style
    case lighting
    case camera
    case environment
    case material
    case composition
    case rendering

    public var displayName: String {
        switch self {
        case .subject: "主体"
        case .style: "风格"
        case .lighting: "光线"
        case .camera: "镜头"
        case .environment: "环境"
        case .material: "材质"
        case .composition: "构图"
        case .rendering: "渲染"
        }
    }
}

public enum PromptEvidence: String, Codable, Sendable {
    case observable
    case inferred
    case userProvided
}

public enum PromptModuleRole: Codable, Equatable, Hashable, Sendable {
    case visual(PromptModuleCategory)
    case instruction

    public var visualCategory: PromptModuleCategory? {
        guard case .visual(let category) = self else { return nil }
        return category
    }

    public var isUserEditableText: Bool {
        switch self {
        case .instruction: true
        case .visual: false
        }
    }
}

public struct PromptEvidenceClaim: Codable, Equatable, Sendable {
    public var kind: PromptEvidence
    public var statement: String

    public init(kind: PromptEvidence, statement: String) {
        self.kind = kind
        self.statement = statement
    }
}

public struct PromptModule: Codable, Equatable, Identifiable, Sendable {
    public var id: PromptModuleID
    public var role: PromptModuleRole
    public var content: String
    public var sourceAssetID: AssetID?
    public var sourceAnalysisSnapshotID: AnalysisSnapshotID?
    public var evidence: PromptEvidence
    public var evidenceClaims: [PromptEvidenceClaim]
    public var isEnabled: Bool
    public var isLocked: Bool
    public var revision: Int
    public var createdAt: Date
    public var updatedAt: Date

    public var category: PromptModuleCategory? { role.visualCategory }

    public init(
        id: PromptModuleID = PromptModuleID(),
        role: PromptModuleRole,
        content: String,
        sourceAssetID: AssetID? = nil,
        sourceAnalysisSnapshotID: AnalysisSnapshotID? = nil,
        evidence: PromptEvidence,
        evidenceClaims: [PromptEvidenceClaim] = [],
        isEnabled: Bool = true,
        isLocked: Bool = false,
        revision: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.sourceAssetID = sourceAssetID
        self.sourceAnalysisSnapshotID = sourceAnalysisSnapshotID
        self.evidence = evidence
        self.evidenceClaims = evidenceClaims
        self.isEnabled = isEnabled
        self.isLocked = isLocked
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(
        id: PromptModuleID = PromptModuleID(),
        category: PromptModuleCategory,
        content: String,
        sourceAssetID: AssetID? = nil,
        sourceAnalysisSnapshotID: AnalysisSnapshotID? = nil,
        evidence: PromptEvidence,
        evidenceClaims: [PromptEvidenceClaim] = [],
        isEnabled: Bool = true,
        isLocked: Bool = false,
        revision: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.init(
            id: id,
            role: .visual(category),
            content: content,
            sourceAssetID: sourceAssetID,
            sourceAnalysisSnapshotID: sourceAnalysisSnapshotID,
            evidence: evidence,
            evidenceClaims: evidenceClaims,
            isEnabled: isEnabled,
            isLocked: isLocked,
            revision: revision,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case category
        case content
        case sourceAssetID
        case sourceAnalysisSnapshotID
        case evidence
        case evidenceClaims
        case isEnabled
        case isLocked
        case revision
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(PromptModuleID.self, forKey: .id)
        if let decodedRole = try container.decodeIfPresent(PromptModuleRole.self, forKey: .role) {
            role = decodedRole
        } else {
            role = .visual(try container.decode(PromptModuleCategory.self, forKey: .category))
        }
        content = try container.decode(String.self, forKey: .content)
        sourceAssetID = try container.decodeIfPresent(AssetID.self, forKey: .sourceAssetID)
        sourceAnalysisSnapshotID = try container.decodeIfPresent(
            AnalysisSnapshotID.self,
            forKey: .sourceAnalysisSnapshotID
        )
        evidence = try container.decode(PromptEvidence.self, forKey: .evidence)
        evidenceClaims = try container.decodeIfPresent(
            [PromptEvidenceClaim].self,
            forKey: .evidenceClaims
        ) ?? []
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(sourceAssetID, forKey: .sourceAssetID)
        try container.encodeIfPresent(sourceAnalysisSnapshotID, forKey: .sourceAnalysisSnapshotID)
        try container.encode(evidence, forKey: .evidence)
        try container.encode(evidenceClaims, forKey: .evidenceClaims)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(isLocked, forKey: .isLocked)
        try container.encode(revision, forKey: .revision)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

public struct AnalysisSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: AnalysisSnapshotID
    public var assetID: AssetID
    public var providerID: ProviderID
    public var modelID: String
    public var schemaVersion: String
    public var moduleIDs: [PromptModuleID]
    public var createdAt: Date

    public init(
        id: AnalysisSnapshotID = AnalysisSnapshotID(),
        assetID: AssetID,
        providerID: ProviderID,
        modelID: String,
        schemaVersion: String,
        moduleIDs: [PromptModuleID],
        createdAt: Date = .now
    ) {
        self.id = id
        self.assetID = assetID
        self.providerID = providerID
        self.modelID = modelID
        self.schemaVersion = schemaVersion
        self.moduleIDs = moduleIDs
        self.createdAt = createdAt
    }
}

public struct RecipeSlot: Codable, Equatable, Identifiable, Sendable {
    public var category: PromptModuleCategory
    public var moduleIDs: [PromptModuleID]
    public var primaryModuleID: PromptModuleID?
    public var isEnabled: Bool

    public var id: PromptModuleCategory { category }

    public init(
        category: PromptModuleCategory,
        moduleIDs: [PromptModuleID] = [],
        primaryModuleID: PromptModuleID? = nil,
        isEnabled: Bool = true
    ) {
        self.category = category
        self.moduleIDs = moduleIDs
        self.primaryModuleID = primaryModuleID
        self.isEnabled = isEnabled
    }
}

public enum RecipeBindingPriority: String, Codable, Sendable {
    case primary
    case supporting
}

public struct RecipeInputBinding: Codable, Equatable, Identifiable, Sendable {
    public var id: RecipeBindingID
    public var moduleID: PromptModuleID
    public var role: PromptModuleRole
    public var order: Int
    public var priority: RecipeBindingPriority
    public var isEnabled: Bool

    public init(
        id: RecipeBindingID = RecipeBindingID(),
        moduleID: PromptModuleID,
        role: PromptModuleRole,
        order: Int,
        priority: RecipeBindingPriority = .supporting,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.moduleID = moduleID
        self.role = role
        self.order = order
        self.priority = priority
        self.isEnabled = isEnabled
    }
}

public struct PromptOverride: Codable, Equatable, Sendable {
    public var text: String
    public var updatedAt: Date

    public init(text: String, updatedAt: Date = .now) {
        self.text = text
        self.updatedAt = updatedAt
    }
}

public struct CompileTarget: Codable, Equatable, Sendable {
    public var providerID: ProviderID
    public var modelID: String
    public var languageCode: String

    public init(providerID: ProviderID, modelID: String, languageCode: String = "en") {
        self.providerID = providerID
        self.modelID = modelID
        self.languageCode = languageCode
    }
}

public struct Recipe: Codable, Equatable, Identifiable, Sendable {
    public var id: RecipeID
    public var name: String
    public var bindings: [RecipeInputBinding]
    public var target: CompileTarget
    public var promptOverride: PromptOverride?
    public var revision: Int
    public var createdAt: Date
    public var updatedAt: Date

    public var slots: [RecipeSlot] {
        get {
            PromptModuleCategory.allCases.map { category in
                let matches = bindings
                    .filter { $0.role == .visual(category) }
                    .sorted { $0.order < $1.order }
                return RecipeSlot(
                    category: category,
                    moduleIDs: matches.map(\.moduleID),
                    primaryModuleID: matches.first(where: { $0.priority == .primary })?.moduleID,
                    isEnabled: matches.contains(where: \.isEnabled)
                )
            }
        }
        set {
            bindings = Self.bindings(from: newValue)
            revision += 1
            updatedAt = .now
        }
    }

    public init(
        id: RecipeID = RecipeID(),
        name: String,
        bindings: [RecipeInputBinding] = [],
        target: CompileTarget,
        promptOverride: PromptOverride? = nil,
        revision: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.bindings = bindings
        self.target = target
        self.promptOverride = promptOverride
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(
        id: RecipeID = RecipeID(),
        name: String,
        slots: [RecipeSlot],
        target: CompileTarget,
        promptOverride: PromptOverride? = nil,
        revision: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.init(
            id: id,
            name: name,
            bindings: Self.bindings(from: slots),
            target: target,
            promptOverride: promptOverride,
            revision: revision,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case bindings
        case slots
        case target
        case promptOverride
        case revision
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(RecipeID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        if let decodedBindings = try container.decodeIfPresent(
            [RecipeInputBinding].self,
            forKey: .bindings
        ) {
            bindings = decodedBindings
        } else {
            let legacySlots = try container.decodeIfPresent([RecipeSlot].self, forKey: .slots) ?? []
            bindings = Self.bindings(from: legacySlots)
        }
        target = try container.decode(CompileTarget.self, forKey: .target)
        promptOverride = try container.decodeIfPresent(PromptOverride.self, forKey: .promptOverride)
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(bindings, forKey: .bindings)
        try container.encode(target, forKey: .target)
        try container.encodeIfPresent(promptOverride, forKey: .promptOverride)
        try container.encode(revision, forKey: .revision)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    private static func bindings(from slots: [RecipeSlot]) -> [RecipeInputBinding] {
        var nextOrder = 0
        return slots.flatMap { slot in
            slot.moduleIDs.map { moduleID in
                defer { nextOrder += 1 }
                return RecipeInputBinding(
                    moduleID: moduleID,
                    role: .visual(slot.category),
                    order: nextOrder,
                    priority: slot.primaryModuleID == moduleID ? .primary : .supporting,
                    isEnabled: slot.isEnabled
                )
            }
        }
    }
}

public enum CompileWarning: Codable, Equatable, Sendable {
    case missingCategory(PromptModuleCategory)
    case multipleModules(category: PromptModuleCategory, count: Int)
    case duplicateText(category: PromptModuleCategory)
    case missingModule(PromptModuleID)
    case emptyModule(PromptModuleID)
    case roleMismatch(moduleID: PromptModuleID)
}

public struct ModuleInputSnapshot: Codable, Equatable, Sendable {
    public var moduleID: PromptModuleID
    public var revision: Int
    public var role: PromptModuleRole
    public var resolvedContent: String
    public var evidence: PromptEvidence
    public var sourceAssetID: AssetID?
    public var sourceAnalysisSnapshotID: AnalysisSnapshotID?

    public init(
        moduleID: PromptModuleID,
        revision: Int,
        role: PromptModuleRole,
        resolvedContent: String,
        evidence: PromptEvidence,
        sourceAssetID: AssetID? = nil,
        sourceAnalysisSnapshotID: AnalysisSnapshotID? = nil
    ) {
        self.moduleID = moduleID
        self.revision = revision
        self.role = role
        self.resolvedContent = resolvedContent
        self.evidence = evidence
        self.sourceAssetID = sourceAssetID
        self.sourceAnalysisSnapshotID = sourceAnalysisSnapshotID
    }
}

public struct CompiledPromptSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: CompiledPromptID
    public var recipeID: RecipeID
    public var recipeRevision: Int
    public var compilerVersion: String
    public var target: CompileTarget
    public var moduleInputs: [ModuleInputSnapshot]
    public var baseText: String
    public var finalText: String
    public var override: PromptOverride?
    public var sourceModuleIDs: [PromptModuleID]
    public var warnings: [CompileWarning]
    public var inputFingerprint: String
    public var createdAt: Date

    public init(
        id: CompiledPromptID = CompiledPromptID(),
        recipeID: RecipeID,
        recipeRevision: Int = 0,
        compilerVersion: String = "legacy",
        target: CompileTarget,
        moduleInputs: [ModuleInputSnapshot] = [],
        baseText: String,
        finalText: String,
        override: PromptOverride?,
        sourceModuleIDs: [PromptModuleID],
        warnings: [CompileWarning],
        inputFingerprint: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.recipeID = recipeID
        self.recipeRevision = recipeRevision
        self.compilerVersion = compilerVersion
        self.target = target
        self.moduleInputs = moduleInputs
        self.baseText = baseText
        self.finalText = finalText
        self.override = override
        self.sourceModuleIDs = sourceModuleIDs
        self.warnings = warnings
        self.inputFingerprint = inputFingerprint
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case recipeID
        case recipeRevision
        case compilerVersion
        case target
        case moduleInputs
        case baseText
        case finalText
        case override
        case sourceModuleIDs
        case warnings
        case inputFingerprint
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(CompiledPromptID.self, forKey: .id)
        recipeID = try container.decode(RecipeID.self, forKey: .recipeID)
        recipeRevision = try container.decodeIfPresent(Int.self, forKey: .recipeRevision) ?? 0
        compilerVersion = try container.decodeIfPresent(String.self, forKey: .compilerVersion) ?? "legacy"
        target = try container.decode(CompileTarget.self, forKey: .target)
        moduleInputs = try container.decodeIfPresent(
            [ModuleInputSnapshot].self,
            forKey: .moduleInputs
        ) ?? []
        baseText = try container.decode(String.self, forKey: .baseText)
        finalText = try container.decode(String.self, forKey: .finalText)
        override = try container.decodeIfPresent(PromptOverride.self, forKey: .override)
        sourceModuleIDs = try container.decodeIfPresent(
            [PromptModuleID].self,
            forKey: .sourceModuleIDs
        ) ?? moduleInputs.map(\.moduleID)
        warnings = try container.decodeIfPresent([CompileWarning].self, forKey: .warnings) ?? []
        inputFingerprint = try container.decodeIfPresent(String.self, forKey: .inputFingerprint) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(recipeID, forKey: .recipeID)
        try container.encode(recipeRevision, forKey: .recipeRevision)
        try container.encode(compilerVersion, forKey: .compilerVersion)
        try container.encode(target, forKey: .target)
        try container.encode(moduleInputs, forKey: .moduleInputs)
        try container.encode(baseText, forKey: .baseText)
        try container.encode(finalText, forKey: .finalText)
        try container.encodeIfPresent(override, forKey: .override)
        try container.encode(sourceModuleIDs, forKey: .sourceModuleIDs)
        try container.encode(warnings, forKey: .warnings)
        try container.encode(inputFingerprint, forKey: .inputFingerprint)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

public enum GeneratorAssetRole: String, Codable, CaseIterable, Sendable {
    case general
    case identity
    case environment
    case style
    case composition
    case palette
    case structure

    /// Roles offered by the current canvas interaction. The remaining cases
    /// stay decodable so older workspaces keep opening without data loss.
    public static let assignableCases: [Self] = [
        .identity,
        .environment,
        .style,
        .palette
    ]
}

public struct GeneratorAssetBinding: Codable, Equatable, Identifiable, Sendable {
    public var id: GeneratorAssetBindingID
    public var assetID: AssetID
    /// The canvas occurrence from which this reference was connected.
    ///
    /// Assets may have several canvas occurrences after copy/paste. Retaining
    /// this optional identity keeps the visual connection anchored to the
    /// occurrence the user actually dragged, rather than re-resolving by
    /// proximity whenever the canvas changes.
    public var sourceCanvasNodeID: CanvasNodeID?
    public var role: GeneratorAssetRole
    public var order: Int
    public var isEnabled: Bool

    public init(
        id: GeneratorAssetBindingID = GeneratorAssetBindingID(),
        assetID: AssetID,
        sourceCanvasNodeID: CanvasNodeID? = nil,
        role: GeneratorAssetRole,
        order: Int,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.assetID = assetID
        self.sourceCanvasNodeID = sourceCanvasNodeID
        self.role = role
        self.order = order
        self.isEnabled = isEnabled
    }
}

/// The media modality produced by one generation action.
///
/// This stays independent from `AssetMediaKind`: a generator has a concrete
/// output contract, while an asset may still have an unknown MIME type.
public enum GenerationMediaKind: String, Codable, CaseIterable, Sendable {
    case image
    case video
}

/// Editable state for the semantic-mask image editing beta.
///
/// The mask is a project-managed PNG whose white pixels identify the region
/// the model may edit and whose black pixels identify protected content.
public struct ImageEditConfiguration: Codable, Equatable, Sendable {
    public var sourceAssetID: AssetID
    public var maskRelativePath: String
    public var maskPixelSize: PixelSize
    public var maskContentHash: String?

    public init(
        sourceAssetID: AssetID,
        maskRelativePath: String,
        maskPixelSize: PixelSize,
        maskContentHash: String? = nil
    ) {
        self.sourceAssetID = sourceAssetID
        self.maskRelativePath = maskRelativePath
        self.maskPixelSize = maskPixelSize
        self.maskContentHash = maskContentHash
    }
}

/// Immutable edit provenance captured when a generation run is created.
///
/// Source metadata is frozen separately from the mutable `Asset`, while the
/// mask continues to use a project-relative managed path for package safety.
public struct ImageEditSnapshot: Codable, Equatable, Sendable {
    public var sourceAssetID: AssetID
    public var sourcePixelSize: PixelSize?
    public var sourceContentHash: String?
    public var maskRelativePath: String
    public var maskPixelSize: PixelSize
    public var maskContentHash: String?

    public init(
        sourceAssetID: AssetID,
        sourcePixelSize: PixelSize? = nil,
        sourceContentHash: String? = nil,
        maskRelativePath: String,
        maskPixelSize: PixelSize,
        maskContentHash: String? = nil
    ) {
        self.sourceAssetID = sourceAssetID
        self.sourcePixelSize = sourcePixelSize
        self.sourceContentHash = sourceContentHash
        self.maskRelativePath = maskRelativePath
        self.maskPixelSize = maskPixelSize
        self.maskContentHash = maskContentHash
    }
}

public struct GenerationParameters: Codable, Equatable, Sendable {
    public static let supportedVariationCount = 1 ... 4
    public static let supportedVideoDurationSeconds = 3 ... 10
    public static let defaultVideoDurationSeconds = 10
    public static let videoDurationProviderOptionKey = "durationSeconds"

    public var aspectRatio: String
    public var seed: Int?
    public var variationCount: Int
    public var providerOptions: [String: String]

    public init(
        aspectRatio: String = "16:9",
        seed: Int? = nil,
        variationCount: Int = 1,
        providerOptions: [String: String] = [:]
    ) {
        self.aspectRatio = aspectRatio
        self.seed = seed
        self.variationCount = Self.normalizedVariationCount(variationCount)
        self.providerOptions = providerOptions
    }

    public static func normalizedVariationCount(_ count: Int) -> Int {
        min(max(count, supportedVariationCount.lowerBound), supportedVariationCount.upperBound)
    }

    public static func normalizedVideoDurationSeconds(_ seconds: Int) -> Int {
        min(
            max(seconds, supportedVideoDurationSeconds.lowerBound),
            supportedVideoDurationSeconds.upperBound
        )
    }

    public var videoDurationSeconds: Int {
        guard let rawValue = providerOptions[Self.videoDurationProviderOptionKey],
              let seconds = Int(rawValue) else {
            return Self.defaultVideoDurationSeconds
        }
        return Self.normalizedVideoDurationSeconds(seconds)
    }

    private enum CodingKeys: String, CodingKey {
        case aspectRatio
        case seed
        case variationCount
        case providerOptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        aspectRatio = try container.decodeIfPresent(String.self, forKey: .aspectRatio) ?? "16:9"
        seed = try container.decodeIfPresent(Int.self, forKey: .seed)
        variationCount = Self.normalizedVariationCount(
            try container.decodeIfPresent(Int.self, forKey: .variationCount) ?? 1
        )
        providerOptions = try container.decodeIfPresent(
            [String: String].self,
            forKey: .providerOptions
        ) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(aspectRatio, forKey: .aspectRatio)
        try container.encodeIfPresent(seed, forKey: .seed)
        try container.encode(
            Self.normalizedVariationCount(variationCount),
            forKey: .variationCount
        )
        try container.encode(providerOptions, forKey: .providerOptions)
    }
}

public struct Generator: Codable, Equatable, Identifiable, Sendable {
    public var id: GeneratorID
    public var name: String
    public var recipeID: RecipeID
    /// User-authored prompt owned by this generation action.
    ///
    /// Connected structured modules are compiled around this text at runtime,
    /// but never copied into or removed from this user-authored value.
    public var promptText: String
    public var target: CompileTarget
    public var parameters: GenerationParameters
    public var assetBindings: [GeneratorAssetBinding]
    public var mediaKind: GenerationMediaKind
    public var imageEdit: ImageEditConfiguration?
    public var revision: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: GeneratorID = GeneratorID(),
        name: String,
        recipeID: RecipeID,
        promptText: String = "",
        target: CompileTarget,
        parameters: GenerationParameters = GenerationParameters(),
        assetBindings: [GeneratorAssetBinding] = [],
        mediaKind: GenerationMediaKind = .image,
        imageEdit: ImageEditConfiguration? = nil,
        revision: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.recipeID = recipeID
        self.promptText = promptText
        self.target = target
        self.parameters = parameters
        self.assetBindings = assetBindings
        self.mediaKind = mediaKind
        self.imageEdit = imageEdit
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case recipeID
        case promptText
        case target
        case parameters
        case assetBindings
        case mediaKind
        case imageEdit
        case revision
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(GeneratorID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        recipeID = try container.decode(RecipeID.self, forKey: .recipeID)
        promptText = try container.decodeIfPresent(String.self, forKey: .promptText) ?? ""
        target = try container.decode(CompileTarget.self, forKey: .target)
        parameters = try container.decodeIfPresent(
            GenerationParameters.self,
            forKey: .parameters
        ) ?? GenerationParameters()
        assetBindings = try container.decodeIfPresent(
            [GeneratorAssetBinding].self,
            forKey: .assetBindings
        ) ?? []
        mediaKind = try container.decodeIfPresent(
            GenerationMediaKind.self,
            forKey: .mediaKind
        ) ?? .image
        imageEdit = try container.decodeIfPresent(
            ImageEditConfiguration.self,
            forKey: .imageEdit
        )
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(recipeID, forKey: .recipeID)
        try container.encode(promptText, forKey: .promptText)
        try container.encode(target, forKey: .target)
        try container.encode(parameters, forKey: .parameters)
        try container.encode(assetBindings, forKey: .assetBindings)
        try container.encode(mediaKind, forKey: .mediaKind)
        try container.encodeIfPresent(imageEdit, forKey: .imageEdit)
        try container.encode(revision, forKey: .revision)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

public extension Generator {
    /// Stable, de-duplicated image identities in binding order. One image may
    /// intentionally serve several semantic roles without consuming several
    /// provider reference-image slots.
    var uniqueReferenceAssetIDs: [AssetID] {
        var seen: Set<AssetID> = []
        return assetBindings.compactMap { binding in
            guard seen.insert(binding.assetID).inserted else { return nil }
            return binding.assetID
        }
    }

    var uniqueReferenceAssetCount: Int {
        uniqueReferenceAssetIDs.count
    }

    func hasReferenceBinding(assetID: AssetID, role: GeneratorAssetRole) -> Bool {
        assetBindings.contains { $0.assetID == assetID && $0.role == role }
    }
}

public enum GenerationState: String, Codable, Sendable {
    case queued
    case generating
    case partial
    case succeeded
    case failed
    case cancelled
}

public struct GenerationRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: GenerationID
    public var generatorID: GeneratorID?
    public var retryOfGenerationID: GenerationID?
    public var recipeID: RecipeID
    public var promptSnapshotID: CompiledPromptID
    public var providerID: ProviderID
    public var modelID: String
    public var aspectRatio: String
    public var state: GenerationState
    public var outputAssetIDs: [AssetID]
    public var mediaKind: GenerationMediaKind
    public var imageEditSnapshot: ImageEditSnapshot?
    /// Frozen user-facing context. These snapshots keep history readable after
    /// the editable generator node and recipe have been removed.
    public var generatorNameSnapshot: String?
    public var displayTitle: String?
    public var createdAt: Date

    public init(
        id: GenerationID = GenerationID(),
        generatorID: GeneratorID? = nil,
        retryOfGenerationID: GenerationID? = nil,
        recipeID: RecipeID,
        promptSnapshotID: CompiledPromptID,
        providerID: ProviderID,
        modelID: String,
        aspectRatio: String,
        state: GenerationState = .queued,
        outputAssetIDs: [AssetID] = [],
        mediaKind: GenerationMediaKind = .image,
        imageEditSnapshot: ImageEditSnapshot? = nil,
        generatorNameSnapshot: String? = nil,
        displayTitle: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.generatorID = generatorID
        self.retryOfGenerationID = retryOfGenerationID
        self.recipeID = recipeID
        self.promptSnapshotID = promptSnapshotID
        self.providerID = providerID
        self.modelID = modelID
        self.aspectRatio = aspectRatio
        self.state = state
        self.outputAssetIDs = outputAssetIDs
        self.mediaKind = mediaKind
        self.imageEditSnapshot = imageEditSnapshot
        self.generatorNameSnapshot = generatorNameSnapshot
        self.displayTitle = displayTitle
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case generatorID
        case retryOfGenerationID
        case recipeID
        case promptSnapshotID
        case providerID
        case modelID
        case aspectRatio
        case state
        case outputAssetIDs
        case mediaKind
        case imageEditSnapshot
        case generatorNameSnapshot
        case displayTitle
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(GenerationID.self, forKey: .id)
        generatorID = try container.decodeIfPresent(GeneratorID.self, forKey: .generatorID)
        retryOfGenerationID = try container.decodeIfPresent(
            GenerationID.self,
            forKey: .retryOfGenerationID
        )
        recipeID = try container.decode(RecipeID.self, forKey: .recipeID)
        promptSnapshotID = try container.decode(CompiledPromptID.self, forKey: .promptSnapshotID)
        providerID = try container.decode(ProviderID.self, forKey: .providerID)
        modelID = try container.decode(String.self, forKey: .modelID)
        aspectRatio = try container.decode(String.self, forKey: .aspectRatio)
        state = try container.decode(GenerationState.self, forKey: .state)
        outputAssetIDs = try container.decodeIfPresent(
            [AssetID].self,
            forKey: .outputAssetIDs
        ) ?? []
        mediaKind = try container.decodeIfPresent(
            GenerationMediaKind.self,
            forKey: .mediaKind
        ) ?? .image
        imageEditSnapshot = try container.decodeIfPresent(
            ImageEditSnapshot.self,
            forKey: .imageEditSnapshot
        )
        generatorNameSnapshot = try container.decodeIfPresent(
            String.self,
            forKey: .generatorNameSnapshot
        )
        displayTitle = try container.decodeIfPresent(String.self, forKey: .displayTitle)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(generatorID, forKey: .generatorID)
        try container.encodeIfPresent(retryOfGenerationID, forKey: .retryOfGenerationID)
        try container.encode(recipeID, forKey: .recipeID)
        try container.encode(promptSnapshotID, forKey: .promptSnapshotID)
        try container.encode(providerID, forKey: .providerID)
        try container.encode(modelID, forKey: .modelID)
        try container.encode(aspectRatio, forKey: .aspectRatio)
        try container.encode(state, forKey: .state)
        try container.encode(outputAssetIDs, forKey: .outputAssetIDs)
        try container.encode(mediaKind, forKey: .mediaKind)
        try container.encodeIfPresent(imageEditSnapshot, forKey: .imageEditSnapshot)
        try container.encodeIfPresent(generatorNameSnapshot, forKey: .generatorNameSnapshot)
        try container.encodeIfPresent(displayTitle, forKey: .displayTitle)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

/// A persisted, presentation-only grouping of generated image nodes.
///
/// The group organizes existing canvas nodes without expanding the finite
/// `CanvasNodeKind` vocabulary or participating in prompt compilation. A group
/// can outlive its editable generator configuration; in that case
/// `generatorID` is detached while the result images and presentation grouping
/// remain available on the canvas.
public struct CanvasGenerationGroup: Codable, Equatable, Identifiable, Sendable {
    public var id: CanvasGenerationGroupID
    public var generatorID: GeneratorID?
    public var name: String?
    public var memberNodeIDs: [CanvasNodeID]
    public var origin: WorldPoint
    public var isCollapsed: Bool
    public var columns: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: CanvasGenerationGroupID = CanvasGenerationGroupID(),
        generatorID: GeneratorID?,
        name: String? = nil,
        memberNodeIDs: [CanvasNodeID] = [],
        origin: WorldPoint,
        isCollapsed: Bool = false,
        columns: Int = 2,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.generatorID = generatorID
        self.name = name
        self.memberNodeIDs = memberNodeIDs
        self.origin = origin
        self.isCollapsed = isCollapsed
        self.columns = max(1, columns)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum JobKind: String, Codable, Sendable {
    case analysis
    case generation
    case thumbnail
}

public enum JobState: String, Codable, Sendable {
    case queued
    case running
    case succeeded
    case failed
    case cancelled
}

public struct JobRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: JobID
    public var kind: JobKind
    public var state: JobState
    public var subjectID: UUID
    public var message: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: JobID = JobID(),
        kind: JobKind,
        state: JobState = .queued,
        subjectID: UUID,
        message: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.state = state
        self.subjectID = subjectID
        self.message = message
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct Workspace: Codable, Equatable, Identifiable, Sendable {
    public static let currentSchemaVersion = 5

    public var schemaVersion: Int
    public var id: WorkspaceID
    public var title: String
    public var assets: [Asset]
    public var analysisSnapshots: [AnalysisSnapshot]
    public var promptModules: [PromptModule]
    public var textBlocks: [TextBlock]
    public var recipes: [Recipe]
    public var generators: [Generator]
    public var compiledPrompts: [CompiledPromptSnapshot]
    public var generations: [GenerationRecord]
    public var generationGroups: [CanvasGenerationGroup]
    public var jobs: [JobRecord]
    public var canvasNodes: [CanvasNode]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        schemaVersion: Int = Workspace.currentSchemaVersion,
        id: WorkspaceID = WorkspaceID(),
        title: String,
        assets: [Asset] = [],
        analysisSnapshots: [AnalysisSnapshot] = [],
        promptModules: [PromptModule] = [],
        textBlocks: [TextBlock] = [],
        recipes: [Recipe] = [],
        generators: [Generator] = [],
        compiledPrompts: [CompiledPromptSnapshot] = [],
        generations: [GenerationRecord] = [],
        generationGroups: [CanvasGenerationGroup] = [],
        jobs: [JobRecord] = [],
        canvasNodes: [CanvasNode] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.assets = assets
        self.analysisSnapshots = analysisSnapshots
        self.promptModules = promptModules
        self.textBlocks = textBlocks
        self.recipes = recipes
        self.generators = generators
        self.compiledPrompts = compiledPrompts
        self.generations = generations
        self.generationGroups = generationGroups
        self.jobs = jobs
        self.canvasNodes = canvasNodes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case title
        case assets
        case analysisSnapshots
        case promptModules
        case textBlocks
        case recipes
        case generators
        case compiledPrompts
        case generations
        case generationGroups
        case jobs
        case canvasNodes
        case createdAt
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? Workspace.currentSchemaVersion
        id = try container.decode(WorkspaceID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        assets = try container.decodeIfPresent([Asset].self, forKey: .assets) ?? []
        analysisSnapshots = try container.decodeIfPresent(
            [AnalysisSnapshot].self,
            forKey: .analysisSnapshots
        ) ?? []
        promptModules = try container.decodeIfPresent(
            [PromptModule].self,
            forKey: .promptModules
        ) ?? []
        textBlocks = try container.decodeIfPresent([TextBlock].self, forKey: .textBlocks) ?? []
        recipes = try container.decodeIfPresent([Recipe].self, forKey: .recipes) ?? []
        generators = try container.decodeIfPresent([Generator].self, forKey: .generators) ?? []
        compiledPrompts = try container.decodeIfPresent(
            [CompiledPromptSnapshot].self,
            forKey: .compiledPrompts
        ) ?? []
        generations = try container.decodeIfPresent(
            [GenerationRecord].self,
            forKey: .generations
        ) ?? []
        generationGroups = try container.decodeIfPresent(
            [CanvasGenerationGroup].self,
            forKey: .generationGroups
        ) ?? []
        jobs = try container.decodeIfPresent([JobRecord].self, forKey: .jobs) ?? []
        canvasNodes = try container.decodeIfPresent([CanvasNode].self, forKey: .canvasNodes) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(assets, forKey: .assets)
        try container.encode(analysisSnapshots, forKey: .analysisSnapshots)
        try container.encode(promptModules, forKey: .promptModules)
        try container.encode(textBlocks, forKey: .textBlocks)
        try container.encode(recipes, forKey: .recipes)
        try container.encode(generators, forKey: .generators)
        try container.encode(compiledPrompts, forKey: .compiledPrompts)
        try container.encode(generations, forKey: .generations)
        try container.encode(generationGroups, forKey: .generationGroups)
        try container.encode(jobs, forKey: .jobs)
        try container.encode(canvasNodes, forKey: .canvasNodes)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
