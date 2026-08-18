import AppKit
import Foundation
import ImageLensCanvas
import ImageLensCore
import ImageLensPersistence
import ImageLensProviders
import Observation

/// Serializes manifest writes issued by `WorkspaceSession`.
///
/// The repository is an actor, but a write that already crossed into that
/// actor cannot be cancelled safely. Storage cleanup therefore enters a short
/// maintenance period: it first drains every already-enqueued write, performs
/// its manifest update exclusively, and asks the session to submit one fresh
/// snapshot after the period ends. Writes requested while maintenance is
/// active are deliberately discarded rather than replayed later, because
/// their snapshots may still refer to files cleanup has removed.
actor WorkspaceManifestSaveCoordinator {
    typealias SaveOperation = @Sendable () async throws -> Void

    private var nextSaveID: UInt64 = 0
    private var saveTail: (id: UInt64, task: Task<Void, Error>)?
    private var isMaintenanceInProgress = false
    private var needsPostMaintenanceSave = false

    /// Appends a manifest write after every prior write and waits for its
    /// result. Returns `false` if storage maintenance intentionally deferred
    /// the request; callers must not replay its captured snapshot.
    @discardableResult
    func save(_ operation: @escaping SaveOperation) async throws -> Bool {
        guard !isMaintenanceInProgress else {
            needsPostMaintenanceSave = true
            return false
        }
        return try await appendAndWait(operation)
    }

    /// Starts an exclusive storage-maintenance period and drains all writes
    /// that already entered the coordinator. New save requests are recorded
    /// only as a need for a fresh snapshot after maintenance completes.
    @discardableResult
    func beginMaintenance() async -> Bool {
        guard !isMaintenanceInProgress else { return false }
        isMaintenanceInProgress = true

        guard let tail = saveTail else { return true }
        _ = await tail.task.result
        if saveTail?.id == tail.id {
            saveTail = nil
        }
        return true
    }

    /// Runs the cleanup manifest write after `beginMaintenance()` has drained
    /// the normal write tail. It must only be used by the maintenance owner.
    func saveDuringMaintenance(_ operation: @escaping SaveOperation) async throws {
        guard isMaintenanceInProgress else {
            _ = try await appendAndWait(operation)
            return
        }
        try await operation()
    }

    /// Ends maintenance and reports whether any save was requested while the
    /// workspace was being cleaned. The caller must persist its *current*
    /// workspace snapshot instead of any snapshot captured during maintenance.
    func endMaintenance() -> Bool {
        guard isMaintenanceInProgress else { return false }
        isMaintenanceInProgress = false
        let needsSave = needsPostMaintenanceSave
        needsPostMaintenanceSave = false
        return needsSave
    }

    func maintenanceIsActive() -> Bool {
        isMaintenanceInProgress
    }

    @discardableResult
    private func appendAndWait(_ operation: @escaping SaveOperation) async throws -> Bool {
        nextSaveID &+= 1
        let saveID = nextSaveID
        let previous = saveTail?.task
        let task = Task<Void, Error> {
            _ = await previous?.result
            try await operation()
        }
        saveTail = (saveID, task)

        let result = await task.result
        if saveTail?.id == saveID {
            saveTail = nil
        }
        try result.get()
        return true
    }
}

struct GeneratorOutputBatch: Identifiable, Equatable {
    let generation: GenerationRecord
    let assets: [Asset]

    var id: GenerationID { generation.id }
}

struct ProjectStorageSnapshot: Equatable {
    let usage: WorkspaceStorageUsage
    let removableAssetCount: Int
    let removableFileCount: Int
    let reclaimableBytes: Int64
}

struct MaskEditorPresentation: Identifiable, Equatable {
    let sourceAssetID: AssetID
    let generatorID: GeneratorID?

    var id: String {
        "\(sourceAssetID.rawValue.uuidString)-\(generatorID?.rawValue.uuidString ?? "new")"
    }
}

@MainActor
@Observable
final class WorkspaceSession {
    private(set) var workspace = Workspace(title: "Untitled Workspace")
    var selectedSection: StudioSection? = .layers
    var selectedLibraryAssetID: AssetID?
    var selectedGenerationID: GenerationID?
    var selectedRunID: WorkspaceRunID?
    private var primarySelectedNodeID: CanvasNodeID?
    private(set) var selectedNodeIDs: Set<CanvasNodeID> = []
    var selectedNodeID: CanvasNodeID? {
        get { primarySelectedNodeID }
        set {
            primarySelectedNodeID = newValue
            selectedNodeIDs = newValue.map { [$0] } ?? []
        }
    }
    var isInspectorPresented = true
    var isReady = false
    var isImporting = false
    var errorMessage: String?
    var statusMessage: String?
    var viewport = ViewportTransform.identity
    private(set) var undoDepth = 0
    private(set) var redoDepth = 0
    private(set) var activeAnalysisAssetIDs: Set<AssetID> = []
    private(set) var activeGenerationGeneratorIDs: Set<GeneratorID> = []
    var activeVideoNodeID: CanvasNodeID?
    var maskEditorPresentation: MaskEditorPresentation?

    let minimumScale = 0.2
    let maximumScale = 4.0

    let packageURL: URL
    private let repository: WorkspacePackageRepository
    let providerSettings: ProviderSettingsStore
    private let placementPolicy = CanvasNodePlacementPolicy.studioDefault
    private let generatedImagePlacement = FixedWidthImageGridPlacement()
    private let generationGroupLayout = GenerationGroupLayoutPolicy()
    @ObservationIgnored private let manifestSaveCoordinator = WorkspaceManifestSaveCoordinator()
    @ObservationIgnored private var pendingSaveTask: Task<Void, Never>?
    /// Incremented whenever an exclusive manifest operation invalidates a
    /// delayed save. A task may already have passed `cancel()` and be waiting
    /// for the main actor, so the token is checked again immediately before it
    /// can capture a workspace snapshot.
    @ObservationIgnored private var saveGeneration: UInt64 = 0
    @ObservationIgnored private var analysisTasks: [AssetID: Task<Void, Never>] = [:]
    @ObservationIgnored private var generationTasks: [GeneratorID: Task<Void, Never>] = [:]
    @ObservationIgnored private var undoStack: [Workspace] = []
    @ObservationIgnored private var redoStack: [Workspace] = []
    @ObservationIgnored private var canvasNodeClipboard: CanvasNodeCopyPayload?
    @ObservationIgnored private var canvasNodePasteCount = 0
    @ObservationIgnored private var canvasNodeClipboardToken: String?

    init(
        packageURL: URL = WorkspaceSession.defaultPackageURL(),
        repository: WorkspacePackageRepository = WorkspacePackageRepository(),
        providerSettings: ProviderSettingsStore = .shared
    ) {
        self.packageURL = packageURL
        self.repository = repository
        self.providerSettings = providerSettings
    }

    var title: String { workspace.title }

    var hasActiveFileProducingTasks: Bool {
        isImporting || !activeAnalysisAssetIDs.isEmpty || !activeGenerationGeneratorIDs.isEmpty
    }

    var collapsedGeneratorNodeHeight: Double {
        placementPolicy.generationSize.height
    }

    var selectedNode: CanvasNode? {
        guard let selectedNodeID else { return nil }
        return workspace.canvasNodes.first { $0.id == selectedNodeID }
    }

    var selectedAsset: Asset? {
        guard let assetID = selectedNode?.imageAssetID else { return nil }
        return asset(for: assetID)
    }

    var selectedLibraryAsset: Asset? {
        guard let selectedLibraryAssetID else { return nil }
        return asset(for: selectedLibraryAssetID)
    }

    var selectedGeneration: GenerationRecord? {
        guard let selectedGenerationID else { return nil }
        return workspace.generations.first { $0.id == selectedGenerationID }
    }

    var libraryAssets: [Asset] {
        WorkspaceCatalogProjection.libraryAssets(from: workspace.assets)
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    var generationHistoryItems: [GenerationHistoryItem] {
        WorkspaceCatalogProjection.generationHistory(
            records: workspace.generations,
            generators: workspace.generators,
            compiledPrompts: workspace.compiledPrompts,
            recipes: workspace.recipes
        )
    }

    var runHistoryItems: [WorkspaceRunItem] {
        WorkspaceRunProjection.userVisibleRuns(in: workspace)
    }

    var canvasGenerators: [Generator] {
        let visibleGeneratorIDs = Set(workspace.canvasNodes.compactMap(\.generatorID))
        return workspace.generators.filter { visibleGeneratorIDs.contains($0.id) }
    }

    func generationGroup(for generatorID: GeneratorID) -> CanvasGenerationGroup? {
        workspace.generationGroups.first { $0.generatorID == generatorID }
    }

    func generationGroup(id: CanvasGenerationGroupID) -> CanvasGenerationGroup? {
        workspace.generationGroups.first { $0.id == id }
    }

    func generationGroup(containing nodeID: CanvasNodeID) -> CanvasGenerationGroup? {
        workspace.generationGroups.first { $0.memberNodeIDs.contains(nodeID) }
    }

    func generationGroupMembers(_ group: CanvasGenerationGroup) -> [CanvasNode] {
        let nodesByID = Dictionary(uniqueKeysWithValues: workspace.canvasNodes.map { ($0.id, $0) })
        return group.memberNodeIDs.compactMap { nodesByID[$0] }
    }

    func generationGroupLayout(for group: CanvasGenerationGroup) -> GenerationGroupLayout {
        generationGroupLayout.layout(
            members: generationGroupMembers(group),
            origin: group.origin,
            columns: group.columns,
            isCollapsed: group.isCollapsed
        )
    }

    var collapsedGenerationGroupMemberNodeIDs: Set<CanvasNodeID> {
        Set(
            workspace.generationGroups
                .filter(\.isCollapsed)
                .flatMap(\.memberNodeIDs)
        )
    }

    var selectedPromptModule: PromptModule? {
        guard let moduleID = selectedNode?.promptModuleID else { return nil }
        return promptModule(for: moduleID)
    }

    var selectedTextBlock: TextBlock? {
        guard let textBlockID = selectedNode?.textBlockID else { return nil }
        return textBlock(for: textBlockID)
    }

    func textBlock(for id: TextBlockID) -> TextBlock? {
        workspace.textBlocks.first { $0.id == id }
    }

    var selectedGenerator: Generator? {
        guard let generatorID = selectedNode?.generatorID else { return nil }
        return generator(for: generatorID)
    }

    func bootstrap() async {
        guard !isReady else { return }

        do {
            let manifestURL = WorkspacePackageLayout(packageURL: packageURL).manifestURL
            var workspaceNeedsSave = false
            if FileManager.default.fileExists(atPath: manifestURL.path) {
                workspace = try await repository.load(from: packageURL)
                if recoverInterruptedJobs() {
                    workspaceNeedsSave = true
                    statusMessage = "已恢复工作区；上次退出时未完成的任务已标记为失败，可手动重试。"
                }
            } else {
                try await repository.save(workspace, to: packageURL)
            }

            if await hydrateAssetSizesAndNormalizeGeneratedFrames() {
                workspaceNeedsSave = true
            }
            if normalizeGeneratorNodeMinimumHeights() {
                workspaceNeedsSave = true
            }
            if migrateLegacyGeneratorPromptOverrides() {
                workspaceNeedsSave = true
            }
            if CanvasNodeRemovalPolicy.retireLegacyGenerationResultGroups(
                in: &workspace
            ) {
                workspaceNeedsSave = true
            }
            let prunedGenerators = CanvasNodeRemovalPolicy.pruneOrphanedGenerators(
                in: &workspace
            )
            if prunedGenerators.didChange {
                workspaceNeedsSave = true
                if statusMessage == nil {
                    statusMessage = "已清理此前从画布删除但仍残留的生图配置"
                }
            }
            let prunedPromptModules = CanvasNodeRemovalPolicy
                .pruneOrphanedSourceLessPromptModules(in: &workspace)
            if prunedPromptModules.didChange {
                workspaceNeedsSave = true
                if statusMessage == nil {
                    let count = prunedPromptModules.removedPromptModuleIDs.count
                    statusMessage = count == 1
                        ? "已清理 1 个此前删除后残留的手写提示词"
                        : "已清理 \(count) 个此前删除后残留的手写提示词"
                }
            }
            if repairGenerationGroups() {
                workspaceNeedsSave = true
            }
            if repairWorkspaceDisplayNames() {
                workspaceNeedsSave = true
            }
            if repairGenerationHistoryMetadata() {
                workspaceNeedsSave = true
            }
            if workspaceNeedsSave {
                try await repository.save(workspace, to: packageURL)
            }
            isReady = true
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        // Keep startup focused on the local workspace. Provider credentials
        // are loaded lazily when settings, analysis, or generation needs them,
        // so opening the canvas never triggers a Keychain authorization sheet.
    }

    func importImages(from sourceURLs: [URL], viewportSize: ViewSize) async {
        let visibleRect = viewport.visibleWorldRect(viewportSize: viewportSize)
        let imageSize = placementPolicy.imageSize
        let origin = WorldPoint(
            x: visibleRect.minX + (visibleRect.width - imageSize.width) / 2,
            y: visibleRect.minY + (visibleRect.height - imageSize.height) / 2
        )
        _ = await importImageFiles(from: sourceURLs, startingAt: origin)
    }

    /// Imports Finder file URLs and centers the first image node on the local
    /// view-space drop location. `WorkspacePackageRepository` owns security-
    /// scoped access, managed copying, content hashing, and disk deduplication.
    func importDroppedImages(
        from sourceURLs: [URL],
        at dropViewPoint: ViewPoint
    ) async -> CanvasImageDropResult {
        let dropWorldPoint = viewport.worldPoint(for: dropViewPoint)
        let imageSize = placementPolicy.imageSize
        let origin = WorldPoint(
            x: dropWorldPoint.x - imageSize.width / 2,
            y: dropWorldPoint.y - imageSize.height / 2
        )
        return await importImageFiles(from: sourceURLs, startingAt: origin)
    }

    /// `onDrop` adapter for Finder `public.file-url` item providers. A custom
    /// `DropDelegate` can pass its local `DropInfo.location` as `dropViewPoint`.
    func importDroppedImages(
        from providers: [NSItemProvider],
        at dropViewPoint: ViewPoint
    ) async -> CanvasImageDropResult {
        let loaded = await CanvasImageFileDrop.loadFileURLs(from: providers)
        guard !loaded.fileURLs.isEmpty else {
            let rejections = loaded.rejections.isEmpty
                ? [CanvasImageDropRejection(sourceURL: nil, reason: "没有收到可导入的文件")]
                : loaded.rejections
            errorMessage = rejections.map(\.message).joined(separator: "\n")
            return CanvasImageDropResult(acceptedSourceCount: 0, rejections: rejections)
        }

        let imported = await importDroppedImages(from: loaded.fileURLs, at: dropViewPoint)
        guard !loaded.rejections.isEmpty else { return imported }

        let combinedRejections = loaded.rejections + imported.rejections
        errorMessage = combinedRejections.map(\.message).joined(separator: "\n")
        if imported.isAccepted {
            statusMessage = "部分素材已导入"
        }
        return CanvasImageDropResult(
            acceptedSourceCount: imported.acceptedSourceCount,
            canvasNodeIDs: imported.canvasNodeIDs,
            rejections: combinedRejections
        )
    }

    /// Imports image data or local image/video file URLs from the system
    /// pasteboard. Finder movie copies stay file-backed through the existing
    /// managed import path instead of loading the movie into memory.
    @discardableResult
    func importClipboardMedia(viewportSize: ViewSize) async -> Bool {
        guard isReady, !isImporting else { return false }
        guard let media = CanvasPasteboardReader.media() else {
            errorMessage = "剪贴板里没有可导入的图片或视频。可复制 Finder 中的媒体文件，或先截取图片到剪贴板。"
            return false
        }

        switch media {
        case let .fileURLs(sourceURLs):
            let origin = centeredOrigin(for: placementPolicy.imageSize, viewportSize: viewportSize)
            let result = await importImageFiles(
                from: sourceURLs,
                startingAt: origin,
                alwaysCreateCanvasOccurrences: true
            )
            return result.isAccepted

        case let .imageData(imageData, mimeType, suggestedName):
            return await importClipboardImageData(
                imageData,
                mimeType: mimeType,
                suggestedName: suggestedName,
                viewportSize: viewportSize
            )
        }
    }

    /// Resolves Command-V without regressing the app's lightweight canvas-node
    /// clipboard. A node copy owns the pasteboard generation that existed when
    /// it was made; any subsequent system copy switches Command-V back to media.
    func pasteCanvasContent(viewportSize: ViewSize) async {
        if hasCurrentCanvasNodeClipboard {
            pasteCopiedCanvasNodes()
            return
        }
        _ = await importClipboardMedia(viewportSize: viewportSize)
    }

    private func importClipboardImageData(
        _ imageData: Data,
        mimeType: String,
        suggestedName: String,
        viewportSize: ViewSize
    ) async -> Bool {
        isImporting = true
        statusMessage = nil
        errorMessage = nil
        defer { isImporting = false }
        do {
            let result = try await repository.importOriginalAssetData(
                imageData,
                mimeType: mimeType,
                suggestedName: suggestedName,
                into: packageURL
            )
            let asset = registerImportedSourceAsset(result)
            let origin = centeredOrigin(for: .image, viewportSize: viewportSize)
            let nodes = placementPolicy.placeImportedImages(
                [asset.id],
                startingAt: origin,
                existingNodes: workspace.canvasNodes
            )
            workspace.canvasNodes.append(contentsOf: nodes)
            selectedNodeID = nodes.first?.id
            statusMessage = "已从剪贴板导入图片"
            await persistWorkspace()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func importImageFiles(
        from sourceURLs: [URL],
        startingAt origin: WorldPoint,
        alwaysCreateCanvasOccurrences: Bool = false
    ) async -> CanvasImageDropResult {
        let validation = CanvasImageFileDrop.validate(sourceURLs)
        var rejections = validation.rejected

        guard isReady else {
            rejections.append(CanvasImageDropRejection(sourceURL: nil, reason: "工作区尚未准备好"))
            errorMessage = rejections.map(\.message).joined(separator: "\n")
            return CanvasImageDropResult(acceptedSourceCount: 0, rejections: rejections)
        }
        guard !isImporting else {
            rejections.append(CanvasImageDropRejection(sourceURL: nil, reason: "另一个导入任务正在进行"))
            errorMessage = rejections.map(\.message).joined(separator: "\n")
            return CanvasImageDropResult(acceptedSourceCount: 0, rejections: rejections)
        }
        guard !validation.accepted.isEmpty else {
            errorMessage = rejections.map(\.message).joined(separator: "\n")
            return CanvasImageDropResult(acceptedSourceCount: 0, rejections: rejections)
        }

        isImporting = true
        statusMessage = nil
        errorMessage = nil
        defer { isImporting = false }

        var acceptedSourceCount = 0
        var assetIDsToPlace: [AssetID] = []
        var existingNodeIDs: [CanvasNodeID] = []

        for sourceURL in validation.accepted {
            do {
                // The repository starts and balances security-scoped access so
                // Finder and sandbox-provided URLs stay valid across this await.
                let result = try await repository.importOriginalAsset(
                    from: sourceURL,
                    into: packageURL
                )

                let assetID = registerImportedSourceAsset(result).id

                acceptedSourceCount += 1
                if !alwaysCreateCanvasOccurrences,
                   let existingNode = workspace.canvasNodes.first(where: { $0.imageAssetID == assetID }) {
                    if !existingNodeIDs.contains(existingNode.id) {
                        existingNodeIDs.append(existingNode.id)
                    }
                } else if !assetIDsToPlace.contains(assetID) {
                    assetIDsToPlace.append(assetID)
                }
            } catch {
                rejections.append(
                    CanvasImageDropRejection(sourceURL: sourceURL, reason: error.localizedDescription)
                )
            }
        }

        var placedNodeIDs: [CanvasNodeID] = []
        if !assetIDsToPlace.isEmpty {
            let nodes = placementPolicy.placeImportedImages(
                assetIDsToPlace,
                startingAt: origin,
                existingNodes: workspace.canvasNodes
            )
            workspace.canvasNodes.append(contentsOf: nodes)
            placedNodeIDs = nodes.map(\.id)
        }

        let resultNodeIDs = existingNodeIDs + placedNodeIDs
        if let primaryNodeID = resultNodeIDs.last {
            setSelection(Set(resultNodeIDs), preferredPrimary: primaryNodeID)
        }

        guard acceptedSourceCount > 0 else {
            errorMessage = rejections.map(\.message).joined(separator: "\n")
            return CanvasImageDropResult(acceptedSourceCount: 0, rejections: rejections)
        }

        do {
            _ = try await saveCurrentWorkspace()
        } catch {
            rejections.append(CanvasImageDropRejection(sourceURL: nil, reason: error.localizedDescription))
        }

        if rejections.isEmpty {
            statusMessage = placedNodeIDs.isEmpty
                ? "素材已在当前画布中"
                : "已导入 \(placedNodeIDs.count) 个素材"
        } else {
            statusMessage = "部分素材已导入"
            errorMessage = rejections.map(\.message).joined(separator: "\n")
        }

        return CanvasImageDropResult(
            acceptedSourceCount: acceptedSourceCount,
            canvasNodeIDs: resultNodeIDs,
            rejections: rejections
        )
    }

    func asset(for id: AssetID) -> Asset? {
        workspace.assets.first { $0.id == id }
    }

    func promptModule(for id: PromptModuleID) -> PromptModule? {
        workspace.promptModules.first { $0.id == id }
    }

    func recipe(for id: RecipeID) -> Recipe? {
        workspace.recipes.first { $0.id == id }
    }

    func generator(for id: GeneratorID) -> Generator? {
        workspace.generators.first { $0.id == id }
    }

    func compiledPreview(for generator: Generator) -> CompiledPromptSnapshot? {
        guard var recipe = recipe(for: generator.recipeID) else { return nil }
        recipe.target = effectiveGenerationTarget(for: generator)
        let authoredPrompt = generator.promptText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
            ? nil
            : PromptOverride(
                text: generator.promptText,
                updatedAt: generator.updatedAt
            )
        return PromptCompiler().compileGeneration(
            recipe: recipe,
            modules: workspace.promptModules,
            authoredPrompt: authoredPrompt
        )
    }

    func effectiveGenerationTarget(for generator: Generator) -> CompileTarget {
        let providerID = generator.target.providerID.rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let modelID = generator.target.modelID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !providerID.isEmpty,
              providerID != "unconfigured",
              !modelID.isEmpty,
              modelID != "unconfigured" else {
            return defaultGenerationTarget
        }
        return generator.target
    }

    private var defaultGenerationTarget: CompileTarget {
        let configuredModelID = providerSettings.generationModel
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return CompileTarget(
            providerID: ImageGenerationModelCatalog.geminiProviderID,
            modelID: configuredModelID.isEmpty
                ? ImageGenerationModelCatalog.gemini.defaultModelID
                : configuredModelID,
            languageCode: "en"
        )
    }

    private var defaultVideoGenerationTarget: CompileTarget {
        CompileTarget(
            providerID: VideoGenerationModelCatalog.geminiProviderID,
            modelID: VideoGenerationModelCatalog.geminiOmniFlash.modelID,
            languageCode: "en"
        )
    }

    func latestAnalysisSnapshot(for assetID: AssetID) -> AnalysisSnapshot? {
        workspace.analysisSnapshots
            .filter { $0.assetID == assetID }
            .max { $0.createdAt < $1.createdAt }
    }

    func analysisModules(for assetID: AssetID) -> [PromptModule] {
        guard let snapshot = latestAnalysisSnapshot(for: assetID) else { return [] }
        let modulesByID = Dictionary(uniqueKeysWithValues: workspace.promptModules.map { ($0.id, $0) })
        return snapshot.moduleIDs.compactMap { modulesByID[$0] }
    }

    func analysisSummary(for assetID: AssetID) -> String? {
        let fragments = analysisModules(for: assetID)
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !fragments.isEmpty else { return nil }
        return fragments.joined(separator: ", ")
    }

    func isPromptModuleOnCanvas(_ moduleID: PromptModuleID) -> Bool {
        workspace.canvasNodes.contains { $0.promptModuleID == moduleID }
    }

    func materializePromptModule(
        id moduleID: PromptModuleID,
        near sourceAssetID: AssetID? = nil
    ) async {
        guard promptModule(for: moduleID) != nil else { return }
        if let existing = workspace.canvasNodes.first(where: { $0.promptModuleID == moduleID }) {
            select(existing.id)
            return
        }

        recordUndoSnapshot()
        let sourceNode = sourceAssetID.flatMap { assetID in
            workspace.canvasNodes.first { $0.imageAssetID == assetID }
        }
        let materializedCount = sourceAssetID.map { assetID in
            workspace.canvasNodes.filter { node in
                guard let existingModuleID = node.promptModuleID,
                      let existingModule = promptModule(for: existingModuleID) else { return false }
                return existingModule.sourceAssetID == assetID
            }.count
        } ?? 0
        let moduleSize = placementPolicy.defaultSize(for: .module)
        let origin = WorldPoint(
            x: (sourceNode?.frame.maxX ?? 0) + 72,
            y: (sourceNode?.frame.minY ?? 0) + Double(materializedCount) * (moduleSize.height + 24)
        )
        let node = placementPolicy.makeNode(
            kind: .module,
            entityID: moduleID.rawValue,
            at: origin,
            zIndex: (workspace.canvasNodes.map(\.zIndex).max() ?? -1) + 1
        )
        workspace.canvasNodes.append(node)
        selectedNodeID = node.id
        statusMessage = "已将选中的结构化提示词放到画布"
        await persistWorkspace()
    }

    /// Places a prompt module with its 280×160 canvas node centered under a
    /// view-space drop point. Existing nodes are moved instead of duplicated.
    func materializePromptModule(
        id moduleID: PromptModuleID,
        at dropViewPoint: ViewPoint
    ) {
        guard promptModule(for: moduleID) != nil else { return }

        let moduleSize = placementPolicy.defaultSize(for: .module)
        let dropWorldPoint = viewport.worldPoint(for: dropViewPoint)
        let destinationOrigin = WorldPoint(
            x: dropWorldPoint.x - moduleSize.width / 2,
            y: dropWorldPoint.y - moduleSize.height / 2
        )

        if let existingNode = workspace.canvasNodes.first(where: { $0.promptModuleID == moduleID }) {
            moveCanvasNode(id: existingNode.id, to: destinationOrigin)
            statusMessage = "已将结构化提示词移动到落点"
            return
        }

        recordUndoSnapshot()
        let node = placementPolicy.makeNode(
            kind: .module,
            entityID: moduleID.rawValue,
            at: destinationOrigin,
            zIndex: (workspace.canvasNodes.map(\.zIndex).max() ?? -1) + 1
        )
        workspace.canvasNodes.append(node)
        setSelection([node.id], preferredPrimary: node.id)
        statusMessage = "已在落点展开结构化提示词"
        scheduleSave()
    }

    func materializeAndConnect(
        moduleID: PromptModuleID,
        sourceAssetID: AssetID?,
        generatorID: GeneratorID
    ) async {
        await materializePromptModule(id: moduleID, near: sourceAssetID)
        await connect(moduleID: moduleID, to: generatorID)
    }

    func collapseAnalysisModuleNodes(for assetID: AssetID) {
        let moduleIDs = Set(
            workspace.promptModules
                .filter { $0.sourceAssetID == assetID }
                .map(\.id)
        )
        guard workspace.canvasNodes.contains(where: { node in
            node.promptModuleID.map(moduleIDs.contains) == true
        }) else { return }
        recordUndoSnapshot()
        workspace.canvasNodes.removeAll { node in
            node.promptModuleID.map(moduleIDs.contains) == true
        }
        selectedNodeID = workspace.canvasNodes.first(where: { $0.imageAssetID == assetID })?.id
        statusMessage = "已收起该图片展开到画布的结构化提示词"
        scheduleSave()
    }

    func isAnalyzing(_ assetID: AssetID) -> Bool {
        activeAnalysisAssetIDs.contains(assetID)
    }

    func isGenerating(_ generatorID: GeneratorID) -> Bool {
        activeGenerationGeneratorIDs.contains(generatorID)
    }

    func startAnalysis(assetID: AssetID) {
        guard analysisTasks[assetID] == nil,
              !activeAnalysisAssetIDs.contains(assetID) else { return }
        guard let asset = asset(for: assetID), asset.supportsReversePrompt else {
            statusMessage = asset(for: assetID)?.isVideo == true
                ? "视频暂不支持提示词拆解"
                : "生成结果保持为纯图片，不再进行提示词拆解"
            return
        }
        guard activeAnalysisAssetIDs.count < 2 else {
            statusMessage = "已有 2 个拆解任务在运行，请完成或取消后再试。"
            return
        }
        // Reserve one of the two analysis lanes before the task reaches its
        // first suspension point. Rapid clicks can no longer overbook the
        // concurrency limit while credentials are loading.
        activeAnalysisAssetIDs.insert(assetID)
        analysisTasks[assetID] = Task { [weak self] in
            await self?.analyze(assetID: assetID)
            self?.activeAnalysisAssetIDs.remove(assetID)
            self?.analysisTasks[assetID] = nil
        }
    }

    func cancelAnalysis(assetID: AssetID) {
        analysisTasks[assetID]?.cancel()
    }

    func startGeneration(generatorID: GeneratorID) {
        // Reserve the single generation lane synchronously. This makes the
        // one-click action safe against rapid clicks on this or another node,
        // even before credential loading reaches its first suspension point.
        guard generationTasks.isEmpty,
              activeGenerationGeneratorIDs.isEmpty else { return }
        activeGenerationGeneratorIDs.insert(generatorID)
        generationTasks[generatorID] = Task { [weak self] in
            await self?.generate(generatorID: generatorID)
            self?.activeGenerationGeneratorIDs.remove(generatorID)
            self?.generationTasks[generatorID] = nil
        }
    }

    func cancelGeneration(generatorID: GeneratorID) {
        generationTasks[generatorID]?.cancel()
    }

    func analyze(assetID: AssetID) async {
        guard isReady, activeAnalysisAssetIDs.contains(assetID),
              let assetIndex = workspace.assets.firstIndex(where: { $0.id == assetID }),
              workspace.assets[assetIndex].supportsReversePrompt else { return }
        await providerSettings.loadCredentialIfNeeded()
        guard let configuration = providerSettings.configuration, providerSettings.hasAPIKey else {
            errorMessage = "请先在“设置 → 服务”中填写并保存 Gemini API Key 与分析模型。"
            return
        }

        workspace.assets[assetIndex].state = .analyzing
        let job = JobRecord(kind: .analysis, state: .running, subjectID: assetID.rawValue)
        workspace.jobs.append(job)
        statusMessage = "正在将图片发送给 Gemini 拆解…"
        await persistWorkspace()

        do {
            try Task.checkCancellation()
            let asset = workspace.assets[assetIndex]
            let data = try await repository.readAssetData(relativePath: asset.relativePath, from: packageURL)
            let client = GeminiProviderClient(configuration: configuration)
            let response = try await client.analyze(
                image: ProviderImageInput(data: data, mimeType: asset.mimeType),
                apiKey: providerSettings.apiKey
            )
            try Task.checkCancellation()

            let snapshotID = AnalysisSnapshotID()
            let outputLanguage: ReversePromptOutputLanguage = configuration.includeChinese ? .chinese : .english
            let modules = response.makePromptModules(
                sourceAssetID: assetID,
                sourceAnalysisSnapshotID: snapshotID,
                language: outputLanguage
            )
            guard !modules.isEmpty else {
                throw GeminiProviderError.emptyResponse
            }
            workspace.promptModules.append(contentsOf: modules)
            workspace.analysisSnapshots.append(
                AnalysisSnapshot(
                    id: snapshotID,
                    assetID: assetID,
                    providerID: "gemini",
                    modelID: configuration.analysisModel,
                    schemaVersion: response.schemaVersion,
                    moduleIDs: modules.map(\.id)
                )
            )

            workspace.assets[assetIndex].state = .ready
            finishJob(id: job.id, state: .succeeded, message: "生成 \(modules.count) 个视觉模块")
            selectedNodeID = workspace.canvasNodes.first(where: { $0.imageAssetID == assetID })?.id
            statusMessage = "分析完成；先查看汇总，需要时再展开结构化提示词"
        } catch is CancellationError {
            workspace.assets[assetIndex].state = .imported
            finishJob(id: job.id, state: .cancelled, message: "用户取消")
            statusMessage = "已取消图片拆解"
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                workspace.assets[assetIndex].state = .imported
                finishJob(id: job.id, state: .cancelled, message: "用户取消")
                statusMessage = "已取消图片拆解"
            } else {
                workspace.assets[assetIndex].state = .failed
                finishJob(id: job.id, state: .failed, message: error.localizedDescription)
                errorMessage = error.localizedDescription
            }
        }
        await persistWorkspace()
    }

    func generate(generatorID: GeneratorID) async {
        guard isReady, activeGenerationGeneratorIDs.contains(generatorID),
              let generatorIndex = workspace.generators.firstIndex(where: { $0.id == generatorID }) else { return }
        let target = effectiveGenerationTarget(for: workspace.generators[generatorIndex])
        guard target.providerID == ImageGenerationModelCatalog.geminiProviderID else {
            errorMessage = "当前版本还未接入 \(target.providerID.rawValue) 生成服务。"
            return
        }
        await providerSettings.loadCredentialIfNeeded()
        guard var configuration = providerSettings.configuration, providerSettings.hasAPIKey else {
            errorMessage = "请先在“设置 → 服务”中填写并保存 Gemini API Key。"
            return
        }
        guard let recipeIndex = workspace.recipes.firstIndex(
            where: { $0.id == workspace.generators[generatorIndex].recipeID }
        ) else { return }

        configuration.generationModel = target.modelID
        if workspace.generators[generatorIndex].target != target {
            workspace.generators[generatorIndex].target = target
            workspace.generators[generatorIndex].revision += 1
            workspace.generators[generatorIndex].updatedAt = .now
        }
        let generator = workspace.generators[generatorIndex]
        let editSnapshot: ImageEditSnapshot?
        if let edit = generator.imageEdit {
            guard generator.mediaKind == .image,
                  let sourceAsset = asset(for: edit.sourceAssetID),
                  sourceAsset.isStillImage else {
                errorMessage = "局部改图的原图已不可用，请重新选择。"
                return
            }
            guard sourceAsset.pixelSize == nil || sourceAsset.pixelSize == edit.maskPixelSize else {
                errorMessage = "蒙版尺寸与原图不一致，请重新绘制蒙版。"
                return
            }
            editSnapshot = ImageEditSnapshot(
                sourceAssetID: sourceAsset.id,
                sourcePixelSize: sourceAsset.pixelSize,
                sourceContentHash: sourceAsset.contentHash,
                maskRelativePath: edit.maskRelativePath,
                maskPixelSize: edit.maskPixelSize,
                maskContentHash: edit.maskContentHash
            )
        } else {
            editSnapshot = nil
        }
        let selfReferenceAssets = generator.uniqueReferenceAssetIDs
            .compactMap(asset(for:))
            .filter {
                !GeneratorReferenceConnectionPolicy.allowsConnection(
                    asset: $0,
                    to: generator.id,
                    generations: workspace.generations
                )
            }
        guard selfReferenceAssets.isEmpty else {
            errorMessage = "不能把该节点自己的生成结果作为参考，请先移除这项连接。"
            return
        }
        let supportedReferenceKinds: Set<AssetMediaKind>
        if generator.mediaKind == .video {
            supportedReferenceKinds = VideoGenerationModelCatalog.model(
                providerID: target.providerID,
                modelID: target.modelID
            )?.supportedReferenceMediaKinds ?? [.image]
        } else {
            supportedReferenceKinds = ImageGenerationModelCatalog.model(
                providerID: target.providerID,
                modelID: target.modelID
            )?.supportedReferenceMediaKinds ?? [.image]
        }
        let incompatibleAssets = generator.uniqueReferenceAssetIDs.compactMap(asset(for:)).filter {
            !supportedReferenceKinds.contains($0.mediaKind)
        }
        if !incompatibleAssets.isEmpty {
            errorMessage = "当前模型不支持已连接的\(incompatibleAssets.contains(where: \.isVideo) ? "视频参考" : "参考素材")。"
            return
        }
        guard let snapshot = compiledPreview(for: generator),
              !snapshot.finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = generator.mediaKind == .video
                ? "请先在视频生成节点中输入提示词。"
                : "请先在图片生成节点中输入提示词。"
            return
        }

        workspace.compiledPrompts.append(snapshot)
        let generation = GenerationRecord(
            generatorID: generatorID,
            retryOfGenerationID: workspace.generations.last(where: {
                $0.generatorID == generatorID && $0.state == .failed
            })?.id,
            recipeID: generator.recipeID,
            promptSnapshotID: snapshot.id,
            providerID: target.providerID,
            modelID: target.modelID,
            aspectRatio: generator.parameters.aspectRatio,
            state: .generating,
            mediaKind: generator.mediaKind,
            imageEditSnapshot: editSnapshot,
            generatorNameSnapshot: generator.name,
            displayTitle: GenerationHistoryTitlePolicy.baseTitle(
                generator: generator,
                compiledPrompt: snapshot,
                recipe: workspace.recipes[recipeIndex]
            )
        )
        workspace.generations.append(generation)
        let job = JobRecord(kind: .generation, state: .running, subjectID: generation.id.rawValue)
        workspace.jobs.append(job)
        let modelName = generator.mediaKind == .video
            ? (VideoGenerationModelCatalog.model(
                providerID: target.providerID,
                modelID: target.modelID
            )?.displayName ?? target.modelID)
            : (ImageGenerationModelCatalog.model(
                providerID: target.providerID,
                modelID: target.modelID
            )?.displayName ?? target.modelID)
        statusMessage = "正在使用 \(modelName) 生成\(generator.mediaKind == .video ? "视频" : "图片")…"
        await persistWorkspace()

        do {
            try Task.checkCancellation()
            let references = try await referenceInputs(for: generator)
            let client = GeminiProviderClient(configuration: configuration)
            let requestedCount = generator.mediaKind == .video
                ? 1
                : GenerationParameters.normalizedVariationCount(generator.parameters.variationCount)
            var payloads: [(data: Data, mimeType: String)] = []
            var partialGenerationError: Error?
            while payloads.count < requestedCount {
                try Task.checkCancellation()
                do {
                    let result: [(data: Data, mimeType: String)]
                    if generator.mediaKind == .video {
                        let videos = try await client.generate(
                            request: VideoGenerationRequest(
                                target: target,
                                prompt: snapshot.finalText,
                                referenceMedia: references,
                                aspectRatio: generator.parameters.aspectRatio,
                                providerOptions: generator.parameters.providerOptions
                            ),
                            credential: providerSettings.apiKey
                        )
                        result = videos.map { ($0.data, $0.mimeType) }
                    } else {
                        let editInput = try await imageEditInput(for: generator)
                        let images = try await client.generate(
                            request: ImageGenerationRequest(
                                target: target,
                                prompt: snapshot.finalText,
                                referenceMedia: references,
                                editInput: editInput,
                                aspectRatio: generator.parameters.aspectRatio,
                                providerOptions: generator.parameters.providerOptions
                            ),
                            credential: providerSettings.apiKey
                        )
                        result = images.map { ($0.data, $0.mimeType) }
                    }
                    guard !result.isEmpty else {
                        throw generator.mediaKind == .video
                            ? GeminiProviderError.noGeneratedVideo
                            : GeminiProviderError.noGeneratedImage
                    }
                    let remainingCount = requestedCount - payloads.count
                    payloads.append(contentsOf: result.prefix(remainingCount))
                } catch {
                    guard !payloads.isEmpty else { throw error }
                    partialGenerationError = error
                    break
                }
            }
            guard !payloads.isEmpty else {
                throw generator.mediaKind == .video
                    ? GeminiProviderError.noGeneratedVideo
                    : GeminiProviderError.noGeneratedImage
            }

            if generator.imageEdit != nil,
               let editInput = try await imageEditInput(for: generator) {
                guard case .inline(let sourceData) = editInput.source.source,
                      case .inline(let maskData) = editInput.mask.source else {
                    throw GeminiProviderError.invalidConfiguration("局部改图素材")
                }
                payloads = try payloads.map { payload in
                    (
                        data: try SemanticMaskCompositor.composite(
                            generatedData: payload.data,
                            sourceData: sourceData,
                            maskData: maskData
                        ),
                        mimeType: "image/png"
                    )
                }
            }

            var assets: [Asset] = []
            for (index, payload) in payloads.enumerated() {
                let result = try await repository.writeDerivedAsset(
                    payload.data,
                    mimeType: payload.mimeType,
                    generationID: generation.id,
                    index: index,
                    into: packageURL
                )
                assets.append(
                    Asset(
                        kind: .generated,
                        state: .ready,
                        displayName: payloads.count == 1
                            ? (generation.displayTitle ?? (generator.mediaKind == .video ? "生成视频" : "生成图片"))
                            : "\(generation.displayTitle ?? "生成结果") \(index + 1)",
                        relativePath: result.relativePath,
                        mimeType: result.mimeType,
                        pixelSize: generator.mediaKind == .image
                            ? ImagePixelSizeReader.pixelSize(from: payload.data)
                            : nil,
                        contentHash: result.contentHash,
                        sourceGenerationID: generation.id
                    )
                )
            }
            workspace.assets.append(contentsOf: assets)
            if let recordIndex = workspace.generations.firstIndex(where: { $0.id == generation.id }) {
                workspace.generations[recordIndex].state = partialGenerationError == nil
                    ? .succeeded
                    : .partial
                workspace.generations[recordIndex].outputAssetIDs = assets.map(\.id)
            }
            finishJob(
                id: job.id,
                state: .succeeded,
                message: partialGenerationError == nil
                    ? "生成 \(assets.count) 个\(generator.mediaKind == .video ? "视频" : "图片")"
                    : "部分完成，生成 \(assets.count) 个\(generator.mediaKind == .video ? "视频" : "图片")"
            )
            statusMessage = partialGenerationError == nil
                ? "生成完成，可在节点中查看\(generator.mediaKind == .video ? "视频" : "图片")"
                : "部分完成，可在节点中查看已生成结果"
        } catch is CancellationError {
            if let recordIndex = workspace.generations.firstIndex(where: { $0.id == generation.id }) {
                workspace.generations[recordIndex].state = .cancelled
            }
            finishJob(id: job.id, state: .cancelled, message: "用户取消")
            statusMessage = "已取消\(generator.mediaKind == .video ? "视频" : "图片")生成任务"
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                if let recordIndex = workspace.generations.firstIndex(where: { $0.id == generation.id }) {
                    workspace.generations[recordIndex].state = .cancelled
                }
                finishJob(id: job.id, state: .cancelled, message: "用户取消")
                statusMessage = "已取消\(generator.mediaKind == .video ? "视频" : "图片")生成任务"
            } else {
                if let recordIndex = workspace.generations.firstIndex(where: { $0.id == generation.id }) {
                    workspace.generations[recordIndex].state = .failed
                }
                finishJob(id: job.id, state: .failed, message: error.localizedDescription)
                errorMessage = error.localizedDescription
            }
        }
        await persistWorkspace()
    }

    func updateGeneratorAspectRatio(id: GeneratorID, aspectRatio: String) {
        guard let index = workspace.generators.firstIndex(where: { $0.id == id }) else { return }
        workspace.generators[index].parameters.aspectRatio = aspectRatio
        workspace.generators[index].revision += 1
        workspace.generators[index].updatedAt = .now
        scheduleSave()
    }

    func updateGeneratorPrompt(id: GeneratorID, text: String) {
        guard let index = workspace.generators.firstIndex(where: { $0.id == id }),
              workspace.generators[index].promptText != text else { return }
        workspace.generators[index].promptText = text
        workspace.generators[index].revision += 1
        workspace.generators[index].updatedAt = .now
        scheduleSave()
    }

    func updateGeneratorVariationCount(id: GeneratorID, count: Int) {
        let normalizedCount = GenerationParameters.normalizedVariationCount(count)
        guard let index = workspace.generators.firstIndex(where: { $0.id == id }),
              workspace.generators[index].parameters.variationCount != normalizedCount else { return }
        workspace.generators[index].parameters.variationCount = normalizedCount
        workspace.generators[index].revision += 1
        workspace.generators[index].updatedAt = .now
        statusMessage = "每次生成 \(normalizedCount) 张图片"
        scheduleSave()
    }

    func updateGeneratorVideoDuration(id: GeneratorID, seconds: Int) {
        let normalizedSeconds = GenerationParameters.normalizedVideoDurationSeconds(seconds)
        guard let index = workspace.generators.firstIndex(where: {
            $0.id == id && $0.mediaKind == .video
        }), workspace.generators[index].parameters.videoDurationSeconds != normalizedSeconds else { return }
        workspace.generators[index].parameters.providerOptions[
            GenerationParameters.videoDurationProviderOptionKey
        ] = String(normalizedSeconds)
        workspace.generators[index].revision += 1
        workspace.generators[index].updatedAt = .now
        statusMessage = "视频时长已设为 \(normalizedSeconds) 秒"
        scheduleSave()
    }

    func updateGeneratorModel(
        id: GeneratorID,
        providerID: ProviderID,
        modelID: String
    ) {
        let normalizedModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !providerID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !normalizedModelID.isEmpty,
              let index = workspace.generators.firstIndex(where: { $0.id == id }) else { return }

        let target = CompileTarget(
            providerID: providerID,
            modelID: normalizedModelID,
            languageCode: workspace.generators[index].target.languageCode
        )
        guard workspace.generators[index].target != target else { return }
        workspace.generators[index].target = target
        workspace.generators[index].revision += 1
        workspace.generators[index].updatedAt = .now
        statusMessage = workspace.generators[index].mediaKind == .video
            ? "已切换视频生成模型"
            : "已切换图片生成模型"
        scheduleSave()
    }

    func renameGenerator(id: GeneratorID, to proposedName: String) {
        let name = WorkspaceDisplayNamePolicy.normalized(proposedName)
        guard !name.isEmpty,
              let index = workspace.generators.firstIndex(where: { $0.id == id }),
              workspace.generators[index].name != name else { return }

        recordUndoSnapshot()
        workspace.generators[index].name = name
        workspace.generators[index].updatedAt = .now
        statusMessage = "已重命名生图节点"
        scheduleSave()
    }

    func renameGenerationGroup(id: CanvasGenerationGroupID, to proposedName: String) {
        let name = WorkspaceDisplayNamePolicy.normalized(proposedName)
        guard !name.isEmpty,
              let index = workspace.generationGroups.firstIndex(where: { $0.id == id }),
              workspace.generationGroups[index].name != name else { return }

        recordUndoSnapshot()
        workspace.generationGroups[index].name = name
        workspace.generationGroups[index].updatedAt = .now
        statusMessage = "已重命名生成结果组"
        scheduleSave()
    }

    func bindReferenceAsset(_ assetID: AssetID, to generatorID: GeneratorID, role: GeneratorAssetRole) async {
        await assignReferenceAsset(assetID, to: generatorID, role: role)
    }

    /// Direct media-to-action connection. A repeated drag never creates a
    /// second hidden role; semantic roles remain an optional advanced setting.
    func assignReferenceAsset(
        _ assetID: AssetID,
        to generatorID: GeneratorID,
        sourceCanvasNodeID: CanvasNodeID? = nil
    ) async {
        guard let generator = generator(for: generatorID) else { return }
        guard !generator.uniqueReferenceAssetIDs.contains(assetID) else {
            statusMessage = "这项素材已经连接到该生成节点"
            return
        }
        await assignReferenceAsset(
            assetID,
            to: generatorID,
            role: .general,
            sourceCanvasNodeID: sourceCanvasNodeID
        )
    }

    /// Assigns a media asset to one semantic reference slot. The same asset may
    /// be bound to several roles, while an exact asset-role pair remains unique.
    /// Assets stay in managed workspace storage; this operation only records
    /// their stable IDs.
    func assignReferenceAsset(
        _ assetID: AssetID,
        to generatorID: GeneratorID,
        role: GeneratorAssetRole,
        sourceCanvasNodeID: CanvasNodeID? = nil
    ) async {
        guard let index = workspace.generators.firstIndex(where: { $0.id == generatorID }) else { return }
        guard let asset = asset(for: assetID), asset.supportsMediaReference else {
            statusMessage = "这项素材暂不支持作为参考"
            return
        }
        guard GeneratorReferenceConnectionPolicy.allowsConnection(
            asset: asset,
            to: generatorID,
            generations: workspace.generations
        ) else {
            statusMessage = "生成结果不能作为同一节点自己的参考"
            return
        }
        if workspace.generators[index].hasReferenceBinding(assetID: assetID, role: role) {
            statusMessage = "这项素材已用于该参考维度"
            return
        }

        let target = effectiveGenerationTarget(for: workspace.generators[index])
        if let model = ImageGenerationModelCatalog.model(
            providerID: target.providerID,
            modelID: target.modelID
        ) {
            guard model.supportedReferenceMediaKinds.contains(asset.mediaKind) else {
                statusMessage = "\(model.displayName) 暂不支持视频参考"
                return
            }
            if !workspace.generators[index].uniqueReferenceAssetIDs.contains(assetID),
               workspace.generators[index].uniqueReferenceAssetCount >= model.maxReferenceImages {
                statusMessage = "\(model.displayName) 最多支持 \(model.maxReferenceImages) 项参考素材"
                return
            }
        }

        recordUndoSnapshot()
        workspace.generators[index].assetBindings.append(
            GeneratorAssetBinding(
                assetID: assetID,
                sourceCanvasNodeID: sourceCanvasNodeID,
                role: role,
                order: workspace.generators[index].assetBindings.count
            )
        )
        workspace.generators[index].revision += 1
        workspace.generators[index].updatedAt = .now
        statusMessage = "已将\(asset.isVideo ? "视频" : "图片")作为“\(role.canvasReferenceTitle)”参考连接"
        await persistWorkspace()
    }

    func unbindReferenceAssetBinding(
        _ bindingID: GeneratorAssetBindingID,
        from generatorID: GeneratorID
    ) async {
        guard let binding = generator(for: generatorID)?.assetBindings.first(
            where: { $0.id == bindingID }
        ) else { return }
        let operation = GraphDisconnectionOperation.generatorAssetBinding(
            generatorID: generatorID,
            bindingID: binding.id,
            assetID: binding.assetID
        )
        _ = await applyGraphDisconnection(
            .accepted(GraphDisconnectionPlan(operations: [operation]))
        ) { _ in "已解除该参考用途" }
    }

    /// Replaces any legacy semantic bindings for one asset with the direct
    /// connection's neutral meaning. This keeps old projects honest: the
    /// thumbnail can reveal a legacy role and the user can explicitly remove
    /// that hidden instruction without deleting the asset itself.
    func useReferenceAssetAsGeneral(_ assetID: AssetID, for generatorID: GeneratorID) async {
        guard let index = workspace.generators.firstIndex(where: { $0.id == generatorID }) else { return }
        let matching = workspace.generators[index].assetBindings.filter { $0.assetID == assetID }
        guard !matching.isEmpty,
              matching.count != 1 || matching[0].role != .general else {
            statusMessage = "这项素材已经是整体参考"
            return
        }

        recordUndoSnapshot()
        let insertionOrder = matching.map(\.order).min() ?? workspace.generators[index].assetBindings.count
        let sourceCanvasNodeID = matching.compactMap(\.sourceCanvasNodeID).first
        workspace.generators[index].assetBindings.removeAll { $0.assetID == assetID }
        workspace.generators[index].assetBindings.append(
            GeneratorAssetBinding(
                assetID: assetID,
                sourceCanvasNodeID: sourceCanvasNodeID,
                role: .general,
                order: insertionOrder
            )
        )
        workspace.generators[index].assetBindings.sort { $0.order < $1.order }
        workspace.generators[index].revision += 1
        workspace.generators[index].updatedAt = .now
        statusMessage = "已改为整体参考"
        await persistWorkspace()
    }

    func unbindReferenceAsset(_ assetID: AssetID, from generatorID: GeneratorID) async {
        guard let generator = generator(for: generatorID) else { return }
        let operations: [GraphDisconnectionOperation] = generator.assetBindings.compactMap { binding in
            guard binding.assetID == assetID else { return nil }
            return GraphDisconnectionOperation.generatorAssetBinding(
                generatorID: generatorID,
                bindingID: binding.id,
                assetID: assetID
            )
        }
        _ = await applyGraphDisconnection(
            .accepted(GraphDisconnectionPlan(operations: operations))
        ) { count in
            count == 1 ? "已断开参考素材连接" : "已断开 \(count) 条参考素材连接"
        }
    }

    func createInstructionModule(viewportSize: ViewSize) async {
        guard isReady else { return }
        let generatorToConnect = selectedGenerator
        let module = PromptModule(
            role: .instruction,
            content: "",
            evidence: .userProvided
        )
        workspace.promptModules.append(module)
        let startingOrigin: WorldPoint
        if let selectedNode, selectedNode.kind == .generation {
            let moduleSize = placementPolicy.defaultSize(for: .module)
            startingOrigin = WorldPoint(
                x: selectedNode.frame.minX - moduleSize.width - 80,
                y: selectedNode.frame.minY + 20
            )
        } else {
            startingOrigin = centeredOrigin(for: .module, viewportSize: viewportSize)
        }
        let nodes = placementPolicy.place(
            kind: .module,
            entityIDs: [module.id.rawValue],
            startingAt: startingOrigin,
            existingNodes: workspace.canvasNodes
        )
        workspace.canvasNodes.append(contentsOf: nodes)
        selectedNodeID = nodes.first?.id
        if let generatorToConnect {
            await connect(moduleID: module.id, to: generatorToConnect.id)
        } else {
            statusMessage = "已新建创作指令"
            await persistWorkspace()
        }
    }

    func createNoteModule(viewportSize: ViewSize) async {
        guard isReady else { return }
        let textBlock = TextBlock()
        workspace.textBlocks.append(textBlock)
        let nodes = placementPolicy.place(
            kind: .text,
            entityIDs: [textBlock.id.rawValue],
            startingAt: centeredOrigin(for: .text, viewportSize: viewportSize),
            existingNodes: workspace.canvasNodes
        )
        workspace.canvasNodes.append(contentsOf: nodes)
        selectedNodeID = nodes.first?.id
        statusMessage = "已新建备注"
        await persistWorkspace()
    }

    func updateTextBlock(id: TextBlockID, text: String) {
        guard let index = workspace.textBlocks.firstIndex(where: { $0.id == id }),
              workspace.textBlocks[index].text != text else { return }
        workspace.textBlocks[index].text = text
        workspace.textBlocks[index].updatedAt = .now
        scheduleSave()
    }

    func createGenerator(viewportSize: ViewSize) async {
        await createGenerator(mediaKind: .image, viewportSize: viewportSize)
    }

    func createGenerator(mediaKind: GenerationMediaKind, viewportSize: ViewSize) async {
        guard isReady else { return }
        let target = mediaKind == .video ? defaultVideoGenerationTarget : defaultGenerationTarget
        let recipe = Recipe(
            name: WorkspaceDisplayNamePolicy.nextDefaultName(
                for: .recipe,
                existingNames: workspace.recipes.map(\.name)
            ),
            target: target
        )
        let generator = Generator(
            name: WorkspaceDisplayNamePolicy.nextDefaultName(
                for: .generator,
                existingNames: workspace.generators.map(\.name)
            ),
            recipeID: recipe.id,
            target: target,
            parameters: GenerationParameters(
                aspectRatio: "16:9",
                variationCount: 1,
                providerOptions: mediaKind == .video
                    ? [
                        GenerationParameters.videoDurationProviderOptionKey:
                            String(GenerationParameters.defaultVideoDurationSeconds)
                    ]
                    : [:]
            ),
            mediaKind: mediaKind
        )
        workspace.recipes.append(recipe)
        workspace.generators.append(generator)
        let startingOrigin: WorldPoint
        if let selectedNode, selectedNode.kind == .module {
            startingOrigin = WorldPoint(
                x: selectedNode.frame.maxX + 80,
                y: selectedNode.frame.minY - 20
            )
        } else {
            startingOrigin = centeredOrigin(for: .generation, viewportSize: viewportSize)
        }
        let nodes = placementPolicy.place(
            kind: .generation,
            entityIDs: [generator.id.rawValue],
            startingAt: startingOrigin,
            existingNodes: workspace.canvasNodes
        )
        workspace.canvasNodes.append(contentsOf: nodes)
        selectedNodeID = nodes.first?.id
        statusMessage = mediaKind == .video
            ? "已新建视频生成节点，可直接输入提示词"
            : "已新建图片生成节点，可直接输入提示词"
        await persistWorkspace()
    }

    func presentMaskEditor(sourceAssetID: AssetID, generatorID: GeneratorID? = nil) {
        guard let asset = asset(for: sourceAssetID), asset.isStillImage else {
            errorMessage = "蒙版局部编辑目前只支持静态图片。"
            return
        }
        maskEditorPresentation = MaskEditorPresentation(
            sourceAssetID: sourceAssetID,
            generatorID: generatorID
        )
    }

    func commitMaskEdit(
        sourceAssetID: AssetID,
        generatorID existingGeneratorID: GeneratorID?,
        pngData: Data,
        pixelSize: PixelSize,
        viewportSize: ViewSize
    ) async {
        guard isReady,
              let sourceAsset = asset(for: sourceAssetID),
              sourceAsset.isStillImage else {
            errorMessage = "用于局部编辑的原图已不可用。"
            return
        }

        let generatorID = existingGeneratorID ?? GeneratorID()
        do {
            let artifact = try await repository.writeMaskArtifact(
                pngData,
                generatorID: generatorID,
                sourceAssetID: sourceAssetID,
                into: packageURL
            )
            let configuration = ImageEditConfiguration(
                sourceAssetID: sourceAssetID,
                maskRelativePath: artifact.relativePath,
                maskPixelSize: pixelSize,
                maskContentHash: artifact.contentHash
            )

            recordUndoSnapshot()
            if let index = workspace.generators.firstIndex(where: { $0.id == generatorID }) {
                guard workspace.generators[index].mediaKind == .image else {
                    errorMessage = "视频生成节点不能切换为图片蒙版编辑。"
                    return
                }
                workspace.generators[index].imageEdit = configuration
                workspace.generators[index].parameters.aspectRatio = sourceAssetAspectRatio(sourceAsset)
                workspace.generators[index].revision += 1
                workspace.generators[index].updatedAt = .now
                selectedNodeID = workspace.canvasNodes.first(where: { $0.generatorID == generatorID })?.id
            } else {
                let target = defaultGenerationTarget
                let recipe = Recipe(
                    name: WorkspaceDisplayNamePolicy.nextDefaultName(
                        for: .recipe,
                        existingNames: workspace.recipes.map(\.name)
                    ),
                    target: target
                )
                let generator = Generator(
                    id: generatorID,
                    name: WorkspaceDisplayNamePolicy.nextDefaultName(
                        for: .generator,
                        existingNames: workspace.generators.map(\.name)
                    ),
                    recipeID: recipe.id,
                    promptText: "",
                    target: target,
                    parameters: GenerationParameters(
                        aspectRatio: sourceAssetAspectRatio(sourceAsset),
                        variationCount: 1
                    ),
                    mediaKind: .image,
                    imageEdit: configuration
                )
                workspace.recipes.append(recipe)
                workspace.generators.append(generator)
                let size = placementPolicy.defaultSize(for: .generation)
                let preferredOrigin: WorldPoint
                if let sourceNode = workspace.canvasNodes.first(where: { $0.imageAssetID == sourceAssetID }) {
                    preferredOrigin = WorldPoint(
                        x: sourceNode.frame.maxX + 80,
                        y: sourceNode.frame.minY
                    )
                } else {
                    preferredOrigin = centeredOrigin(for: size, viewportSize: viewportSize)
                }
                let nodes = placementPolicy.place(
                    kind: .generation,
                    entityIDs: [generatorID.rawValue],
                    startingAt: preferredOrigin,
                    existingNodes: workspace.canvasNodes
                )
                workspace.canvasNodes.append(contentsOf: nodes)
                selectedNodeID = nodes.first?.id
            }
            maskEditorPresentation = nil
            statusMessage = "已创建局部改图节点；输入修改内容后即可生成"
            await persistWorkspace()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeMaskEdit(from generatorID: GeneratorID) {
        guard let index = workspace.generators.firstIndex(where: { $0.id == generatorID }),
              workspace.generators[index].imageEdit != nil else { return }
        recordUndoSnapshot()
        workspace.generators[index].imageEdit = nil
        workspace.generators[index].revision += 1
        workspace.generators[index].updatedAt = .now
        statusMessage = "已移除局部改图蒙版"
        scheduleSave()
    }

    func connect(moduleID: PromptModuleID, to generatorID: GeneratorID) async {
        guard let module = promptModule(for: moduleID),
              let generator = generator(for: generatorID),
              let recipeIndex = workspace.recipes.firstIndex(where: { $0.id == generator.recipeID }) else {
            return
        }
        if let bindingIndex = workspace.recipes[recipeIndex].bindings.firstIndex(
            where: { $0.moduleID == moduleID }
        ) {
            guard !workspace.recipes[recipeIndex].bindings[bindingIndex].isEnabled else {
                statusMessage = "该结构化提示词已经连接到这个\(generator.mediaKind == .video ? "视频" : "图片")生成节点"
                return
            }
            recordUndoSnapshot()
            workspace.recipes[recipeIndex].bindings[bindingIndex].isEnabled = true
            workspace.recipes[recipeIndex].revision += 1
            workspace.recipes[recipeIndex].updatedAt = .now
            statusMessage = "已恢复这条结构化提示词连接"
            await persistWorkspace()
            return
        }

        let recipe = workspace.recipes[recipeIndex]
        let nextOrder = (recipe.bindings.map(\.order).max() ?? -1) + 1
        let hasPrimaryForRole = recipe.bindings.contains {
            $0.role == module.role && $0.priority == .primary
        }
        recordUndoSnapshot()
        workspace.recipes[recipeIndex].bindings.append(
            RecipeInputBinding(
                moduleID: moduleID,
                role: module.role,
                order: nextOrder,
                priority: hasPrimaryForRole ? .supporting : .primary
            )
        )
        workspace.recipes[recipeIndex].revision += 1
        workspace.recipes[recipeIndex].updatedAt = .now
        statusMessage = "已把\(module.category?.displayName ?? "补充")提示词连接到\(generator.mediaKind == .video ? "视频" : "图片")生成节点"
        await persistWorkspace()
    }

    /// Connects a source image's selected analysis modules as one workspace
    /// transaction. The image is only the canvas affordance; the recipe keeps
    /// the same canonical module bindings used by materialized prompt nodes.
    @discardableResult
    func connectAnalysisModules(
        moduleIDs: [PromptModuleID],
        sourceAssetID: AssetID,
        to generatorID: GeneratorID
    ) async -> Bool {
        guard let generator = generator(for: generatorID),
              let recipeIndex = workspace.recipes.firstIndex(
                where: { $0.id == generator.recipeID }
              ) else {
            statusMessage = "没有找到要连接的生成节点"
            return false
        }

        let plan = RecipeBatchConnectionPolicy.plan(
            recipe: workspace.recipes[recipeIndex],
            sourceAssetID: sourceAssetID,
            candidateModuleIDs: moduleIDs,
            availableModules: workspace.promptModules
        )
        guard !plan.addedBindings.isEmpty else {
            statusMessage = plan.skipped.contains(where: { $0.reason == .alreadyBound })
                ? "选中的提示词已经连接到 \(generator.name)"
                : "选中的内容没有可连接的结构化提示词"
            return false
        }

        recordUndoSnapshot()
        workspace.recipes[recipeIndex].bindings.append(contentsOf: plan.addedBindings)
        workspace.recipes[recipeIndex].revision += 1
        workspace.recipes[recipeIndex].updatedAt = .now

        let addedCount = plan.addedBindings.count
        let skippedCount = plan.skipped.count
        statusMessage = skippedCount == 0
            ? "已将 \(addedCount) 项结构化提示词连接到 \(generator.name)"
            : "已连接 \(addedCount) 项，跳过 \(skippedCount) 项已有或无效内容"
        await persistWorkspace()
        return true
    }

    func disconnect(moduleID: PromptModuleID, from generatorID: GeneratorID) async {
        guard let generator = generator(for: generatorID),
              let recipe = recipe(for: generator.recipeID) else {
            return
        }
        let operations: [GraphDisconnectionOperation] = recipe.bindings.compactMap { binding in
            guard binding.moduleID == moduleID else { return nil }
            return GraphDisconnectionOperation.recipeBinding(
                recipeID: recipe.id,
                bindingID: binding.id,
                moduleID: moduleID
            )
        }
        _ = await applyGraphDisconnection(
            .accepted(GraphDisconnectionPlan(operations: operations))
        ) { count in
            count == 1
                ? "已从 \(generator.name) 断开提示词"
                : "已从 \(generator.name) 断开 \(count) 条提示词连接"
        }
    }

    @discardableResult
    func disconnect(graphEdgeID: GraphEdgeID) async -> Bool {
        await applyGraphDisconnection(
            GraphDisconnectionPolicy.decide(
                edgeID: graphEdgeID,
                in: workspace
            )
        ) { count in
            count == 1 ? "已断开连接，可撤销" : "已断开 \(count) 条连接，可撤销"
        }
    }

    @discardableResult
    func disconnectSourceModules(
        _ moduleIDs: [PromptModuleID],
        from groupID: SourceModuleConnectionGroupID
    ) async -> Bool {
        await applyGraphDisconnection(
            GraphDisconnectionPolicy.decide(
                sourceModuleGroupID: groupID,
                moduleIDs: moduleIDs,
                in: workspace
            )
        ) { count in
            count == 1
                ? "已断开 1 项结构化提示词，可撤销"
                : "已断开 \(count) 项结构化提示词，可撤销"
        }
    }

    @discardableResult
    private func applyGraphDisconnection(
        _ decision: GraphDisconnectionDecision,
        successMessage: (Int) -> String
    ) async -> Bool {
        guard case let .accepted(plan) = decision else {
            if case let .rejected(rejection) = decision {
                statusMessage = disconnectionRejectionMessage(rejection)
            }
            return false
        }

        var updatedWorkspace = workspace
        let application = plan.apply(to: &updatedWorkspace)
        guard application.didChange else {
            statusMessage = "连接已经不存在"
            return false
        }

        recordUndoSnapshot()
        workspace = updatedWorkspace
        statusMessage = successMessage(application.removedEdgeIDs.count)
        await persistWorkspace()
        return true
    }

    private func disconnectionRejectionMessage(
        _ rejection: GraphDisconnectionRejection
    ) -> String {
        switch rejection {
        case .readOnlyEdge:
            return "这条线表示来源关系，不能断开"
        case .sourceModuleNotInGroup:
            return "选择的提示词不属于这条连接"
        case .emptySourceModuleSelection:
            return "没有选择要断开的提示词"
        case .missingRecipe,
             .missingGenerator,
             .missingRecipeBinding,
             .missingGeneratorAssetBinding,
             .sourceModuleGroupNotFound:
            return "连接已经不存在"
        }
    }

    func updatePromptModuleContent(id: PromptModuleID, content: String) {
        guard let index = workspace.promptModules.firstIndex(where: { $0.id == id }),
              workspace.promptModules[index].content != content else { return }
        workspace.promptModules[index].content = content
        workspace.promptModules[index].revision += 1
        workspace.promptModules[index].updatedAt = .now

        for recipeIndex in workspace.recipes.indices where workspace.recipes[recipeIndex].bindings.contains(
            where: { $0.moduleID == id }
        ) {
            workspace.recipes[recipeIndex].revision += 1
            workspace.recipes[recipeIndex].updatedAt = .now
        }
        scheduleSave()
    }

    func updatePromptModuleEnabled(id: PromptModuleID, isEnabled: Bool) {
        guard let index = workspace.promptModules.firstIndex(where: { $0.id == id }),
              workspace.promptModules[index].isEnabled != isEnabled else { return }
        workspace.promptModules[index].isEnabled = isEnabled
        workspace.promptModules[index].revision += 1
        workspace.promptModules[index].updatedAt = .now
        for recipeIndex in workspace.recipes.indices where workspace.recipes[recipeIndex].bindings.contains(
            where: { $0.moduleID == id }
        ) {
            workspace.recipes[recipeIndex].revision += 1
            workspace.recipes[recipeIndex].updatedAt = .now
        }
        scheduleSave()
    }

    func connectedModuleIDs(for generator: Generator) -> [PromptModuleID] {
        recipe(for: generator.recipeID)?.bindings
            .filter(\.isEnabled)
            .sorted { $0.order < $1.order }
            .map(\.moduleID) ?? []
    }

    func assetURL(for asset: Asset) -> URL {
        packageURL.appendingPathComponent(asset.relativePath, isDirectory: false)
    }

    func resolvedAssetURL(for asset: Asset) async throws -> URL {
        try await repository.resolveManagedAssetURL(
            relativePath: asset.relativePath,
            from: packageURL
        )
    }

    func imageEditMaskData(for generatorID: GeneratorID) async throws -> Data? {
        guard let edit = generator(for: generatorID)?.imageEdit else { return nil }
        return try await repository.readMaskArtifact(
            relativePath: edit.maskRelativePath,
            from: packageURL
        )
    }

    func exportAsset(_ assetID: AssetID, to destinationURL: URL) async {
        guard let asset = asset(for: assetID) else {
            errorMessage = "要导出的生成结果已不在项目中"
            return
        }
        do {
            try await repository.exportManagedAsset(
                relativePath: asset.relativePath,
                from: packageURL,
                to: destinationURL,
                overwrite: true
            )
            statusMessage = "已导出“\(destinationURL.lastPathComponent)”"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func inspectProjectStorage() async throws -> ProjectStorageSnapshot {
        let plan = try await repository.storageCleanupPlan(for: workspace, at: packageURL)
        return ProjectStorageSnapshot(
            usage: plan.usage,
            removableAssetCount: plan.removableAssetIDs.count,
            removableFileCount: plan.removableFileCount,
            reclaimableBytes: plan.reclaimableBytes
        )
    }

    func cleanUnusedGeneratedResults() async throws -> ProjectStorageSnapshot {
        guard !hasActiveFileProducingTasks else {
            throw CocoaError(
                .fileWriteUnknown,
                userInfo: [NSLocalizedDescriptionKey: "仍有素材导入、分析或生成任务进行中，请完成后再清理。"]
            )
        }

        // `cancel()` only stops a delayed Task that has not yet crossed into
        // `persistWorkspace()`. Invalidate its generation as well, then drain
        // every manifest write already in the repository before calculating a
        // deletion plan or installing the cleaned manifest.
        invalidatePendingSave()
        guard await manifestSaveCoordinator.beginMaintenance() else {
            throw CocoaError(
                .fileWriteUnknown,
                userInfo: [NSLocalizedDescriptionKey: "项目存储清理正在进行中，请稍后再试。"]
            )
        }

        do {
            let plan = try await repository.storageCleanupPlan(for: workspace, at: packageURL)
            let removableIDs = Set(plan.removableAssetIDs)
            let plannedPaths = plan.removableRelativePaths + plan.orphanRelativePaths
            guard !removableIDs.isEmpty || !plannedPaths.isEmpty else {
                let needsFreshSave = await manifestSaveCoordinator.endMaintenance()
                if needsFreshSave {
                    await persistWorkspace()
                }
                return ProjectStorageSnapshot(
                    usage: plan.usage,
                    removableAssetCount: 0,
                    removableFileCount: 0,
                    reclaimableBytes: 0
                )
            }

            let cleanedWorkspace = WorkspaceStorageCleanupPolicy.removingGeneratedAssets(
                removableIDs,
                from: workspace
            )
            // The storage sheet blocks ordinary canvas interaction, but this
            // extra check keeps cleanup correct if another main-actor action
            // changed a reference while the repository was calculating its
            // plan. A path that became referenced must never be deleted.
            let remainingAssetIDs = Set(cleanedWorkspace.assets.map(\.id))
            let removedAssetIDs = Set(workspace.assets.map(\.id))
                .subtracting(remainingAssetIDs)
            let retainedPaths = Set(
                cleanedWorkspace.assets.flatMap { asset in
                    [asset.relativePath, asset.thumbnailRelativePath].compactMap { $0 }
                }
            )
            .union(cleanedWorkspace.generators.compactMap { $0.imageEdit?.maskRelativePath })
            .union(cleanedWorkspace.generations.compactMap { $0.imageEditSnapshot?.maskRelativePath })
            let paths = plannedPaths.filter { !retainedPaths.contains($0) }
            // Update in-memory state before the await. Any edits made while
            // the repository writes are now based on the cleaned workspace;
            // the final fresh save below will retain them.
            workspace = cleanedWorkspace
            undoStack.removeAll()
            redoStack.removeAll()
            updateHistoryDepths()
            if let selectedLibraryAssetID, removedAssetIDs.contains(selectedLibraryAssetID) {
                self.selectedLibraryAssetID = nil
            }

            let cleanedSnapshot = workspace
            try await manifestSaveCoordinator.saveDuringMaintenance { [repository, packageURL] in
                try await repository.save(cleanedSnapshot, to: packageURL)
            }

            do {
                try await repository.removeCleanupFiles(relativePaths: paths, from: packageURL)
            } catch {
                // The manifest is already safe: retrying cleanup can remove any orphan left behind.
                errorMessage = "项目记录已更新，但部分文件未能删除；再次打开存储管理即可重试。\n\(error.localizedDescription)"
            }

            statusMessage = "已清理 \(removedAssetIDs.count) 个当前未使用的生成结果，释放 \(ByteCountFormatter.string(fromByteCount: plan.reclaimableBytes, countStyle: .file))"
            _ = await manifestSaveCoordinator.endMaintenance()
            // Do not replay an old write captured during maintenance. A new
            // snapshot captures any user edits that happened while cleanup was
            // awaiting repository work.
            await persistWorkspace()
            return try await inspectProjectStorage()
        } catch {
            let needsFreshSave = await manifestSaveCoordinator.endMaintenance()
            if needsFreshSave {
                await persistWorkspace()
            }
            throw error
        }
    }

    func isNodeSelected(_ nodeID: CanvasNodeID) -> Bool {
        selectedNodeIDs.contains(nodeID)
    }

    func select(_ nodeID: CanvasNodeID, extending: Bool = false) {
        guard workspace.canvasNodes.contains(where: { $0.id == nodeID }) else { return }
        if extending {
            if selectedNodeIDs.contains(nodeID) {
                selectedNodeIDs.remove(nodeID)
                if primarySelectedNodeID == nodeID {
                    primarySelectedNodeID = topmostSelectedNodeID()
                }
            } else {
                selectedNodeIDs.insert(nodeID)
                primarySelectedNodeID = nodeID
            }
        } else {
            primarySelectedNodeID = nodeID
            selectedNodeIDs = [nodeID]
        }
        isInspectorPresented = true
    }

    func setSelection(_ nodeIDs: Set<CanvasNodeID>, preferredPrimary: CanvasNodeID? = nil) {
        let validNodeIDs = Set(workspace.canvasNodes.lazy.map(\.id)).intersection(nodeIDs)
        selectedNodeIDs = validNodeIDs
        if let preferredPrimary, validNodeIDs.contains(preferredPrimary) {
            primarySelectedNodeID = preferredPrimary
        } else if let primarySelectedNodeID, validNodeIDs.contains(primarySelectedNodeID) {
            self.primarySelectedNodeID = primarySelectedNodeID
        } else {
            primarySelectedNodeID = topmostSelectedNodeID()
        }
    }

    func selectAllCanvasNodes() {
        setSelection(Set(workspace.canvasNodes.map(\.id)))
    }

    func canvasOccurrences(for assetID: AssetID) -> [CanvasNode] {
        workspace.canvasNodes
            .filter { $0.imageAssetID == assetID }
            .sorted { lhs, rhs in
                if lhs.zIndex != rhs.zIndex { return lhs.zIndex > rhs.zIndex }
                return lhs.createdAt > rhs.createdAt
            }
    }

    func selectLibraryAsset(_ assetID: AssetID) {
        guard workspace.assets.contains(where: { $0.id == assetID && $0.isSavedToLibrary }) else {
            return
        }
        clearSelection()
        selectedGenerationID = nil
        selectedRunID = nil
        selectedLibraryAssetID = assetID
        statusMessage = "正在查看素材；只有选择“插入画布”才会加入画布"
    }

    func selectGeneration(_ generationID: GenerationID) {
        selectRun(.generation(generationID))
    }

    func selectRun(_ runID: WorkspaceRunID) {
        guard let run = runHistoryItems.first(where: { $0.id == runID }) else { return }
        selectedLibraryAssetID = nil
        selectedRunID = runID
        switch runID {
        case .generation(let generationID):
            selectedGenerationID = generationID
            statusMessage = "正在查看这次图片生成；选择操作后才会改变画布"
        case .job:
            selectedGenerationID = nil
            if case .asset(let assetID) = run.subject,
               workspace.assets.contains(where: { $0.id == assetID }) {
                statusMessage = "正在查看这次图片分析；可从菜单定位来源图片"
            } else {
                statusMessage = "这次图片分析的来源素材已不在项目中"
            }
        }
    }

    func generationOutputAssets(_ generation: GenerationRecord) -> [Asset] {
        let assetsByID = Dictionary(uniqueKeysWithValues: workspace.assets.map { ($0.id, $0) })
        return generation.outputAssetIDs.compactMap { assetsByID[$0] }
    }

    func generationOutputBatches(for generatorID: GeneratorID) -> [GeneratorOutputBatch] {
        let mediaKind = generator(for: generatorID)?.mediaKind
        return workspace.generations.compactMap { generation -> GeneratorOutputBatch? in
            guard generation.generatorID == generatorID,
                  mediaKind.map({ $0 == generation.mediaKind }) ?? true,
                  generation.state == .succeeded || generation.state == .partial else {
                return nil
            }
            let assets = Array(
                generationOutputAssets(generation)
                    .filter { asset in
                        generation.mediaKind == .video ? asset.isVideo : asset.isStillImage
                    }
                    .prefix(GenerationParameters.supportedVariationCount.upperBound)
            )
            guard !assets.isEmpty else { return nil }
            return GeneratorOutputBatch(generation: generation, assets: assets)
        }
        .sorted { lhs, rhs in
            if lhs.generation.createdAt != rhs.generation.createdAt {
                return lhs.generation.createdAt < rhs.generation.createdAt
            }
            return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
        }
    }

    func latestGenerationOutputAssets(for generatorID: GeneratorID) -> [Asset] {
        generationOutputBatches(for: generatorID).last?.assets ?? []
    }

    func keepAssetInLibrary(_ assetID: AssetID) {
        guard let assetIndex = workspace.assets.firstIndex(where: { $0.id == assetID }),
              workspace.assets[assetIndex].kind == .generated,
              !workspace.assets[assetIndex].isSavedToLibrary else { return }
        workspace.assets[assetIndex].isSavedToLibrary = true
        workspace.assets[assetIndex].addUsage(.material)
        selectedLibraryAssetID = assetID
        statusMessage = "已作为素材保留"
        saveImmediately()
    }

    func removeGeneratedAssetFromLibrary(_ assetID: AssetID) {
        guard let assetIndex = workspace.assets.firstIndex(where: { $0.id == assetID }),
              workspace.assets[assetIndex].kind == .generated,
              workspace.assets[assetIndex].isSavedToLibrary else { return }
        workspace.assets[assetIndex].isSavedToLibrary = false
        workspace.assets[assetIndex].removeUsage(.material)
        if selectedLibraryAssetID == assetID {
            selectedLibraryAssetID = nil
        }
        statusMessage = "已从素材移除；图片仍保留在生成历史"
        saveImmediately()
    }

    @discardableResult
    func focusAssetOnCanvas(_ assetID: AssetID, viewportSize: ViewSize) -> Bool {
        guard let existingNode = canvasOccurrences(for: assetID).first else { return false }
        focusCanvasNode(existingNode.id, viewportSize: viewportSize)
        statusMessage = "已在画布中定位素材"
        return true
    }

    func focusLayerNode(_ nodeID: CanvasNodeID, viewportSize: ViewSize) {
        guard let node = workspace.canvasNodes.first(where: { $0.id == nodeID }) else { return }
        setSelection([nodeID], preferredPrimary: nodeID)
        if let group = generationGroup(containing: nodeID), group.isCollapsed {
            focusWorldRect(generationGroupLayout(for: group).bounds, viewportSize: viewportSize)
        } else {
            focusWorldRect(node.frame, viewportSize: viewportSize)
        }
        statusMessage = "已在画布中定位图层"
    }

    func insertAssetOnCanvas(_ assetID: AssetID, viewportSize: ViewSize) {
        guard let asset = asset(for: assetID) else { return }
        recordUndoSnapshot()
        let size = imageNodeSize(for: asset)
        let origin = availableImageInsertionOrigin(
            centeredAt: centeredOrigin(for: size, viewportSize: viewportSize)
        )
        let node = CanvasNode(
            imageAssetID: assetID,
            frame: WorldRect(origin: origin, size: size),
            zIndex: (workspace.canvasNodes.map(\.zIndex).max() ?? -1) + 1
        )
        workspace.canvasNodes.append(node)
        focusCanvasNode(node.id, viewportSize: viewportSize)
        selectedLibraryAssetID = assetID
        statusMessage = "已将素材插入画布"
        saveImmediately()
    }

    func presentGenerationOnCanvas(_ generationID: GenerationID, viewportSize: ViewSize) {
        guard let generation = workspace.generations.first(where: { $0.id == generationID }) else { return }
        selectedGenerationID = generationID
        selectedRunID = .generation(generationID)
        if let generatorID = generation.generatorID,
           let group = generationGroup(for: generatorID) {
            selectGenerationGroup(group.id)
            focusWorldRect(generationGroupLayout(for: group).bounds, viewportSize: viewportSize)
            statusMessage = "已定位到该生图节点的结果组"
            return
        }
        if let outputAssetID = generation.outputAssetIDs.first(where: { outputID in
            workspace.assets.contains(where: { $0.id == outputID })
        }) {
            selectedLibraryAssetID = outputAssetID
            if !focusAssetOnCanvas(outputAssetID, viewportSize: viewportSize) {
                statusMessage = "这次生成尚未放在画布；可从历史详情中插入"
            }
            return
        }
        if let generatorID = generation.generatorID,
           let generatorNode = workspace.canvasNodes
            .filter({ $0.generatorID == generatorID })
            .max(by: { $0.zIndex < $1.zIndex }) {
            focusCanvasNode(generatorNode.id, viewportSize: viewportSize)
            statusMessage = "该次生成没有可展示结果，已定位到生图节点"
        }
    }

    func removeAssetOccurrencesFromCanvas(_ assetID: AssetID) {
        let occurrenceIDs = Set(canvasOccurrences(for: assetID).map(\.id))
        guard !occurrenceIDs.isEmpty else { return }
        recordUndoSnapshot()
        workspace.canvasNodes.removeAll { occurrenceIDs.contains($0.id) }
        pruneGenerationGroupsAfterNodeRemoval()
        setSelection(selectedNodeIDs.subtracting(occurrenceIDs))
        statusMessage = "已从画布移除素材；原文件仍保留在工作区"
        saveImmediately()
    }

    private func focusCanvasNode(_ nodeID: CanvasNodeID, viewportSize: ViewSize) {
        guard let node = workspace.canvasNodes.first(where: { $0.id == nodeID }) else { return }
        select(nodeID)
        focusWorldRect(node.frame, viewportSize: viewportSize)
    }

    private func focusWorldRect(_ rect: WorldRect, viewportSize: ViewSize) {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }
        let centerX = rect.minX + rect.width / 2
        let centerY = rect.minY + rect.height / 2
        viewport = ViewportTransform(
            scale: viewport.scale,
            translation: ViewPoint(
                x: viewportSize.width / 2 - centerX * viewport.scale,
                y: viewportSize.height / 2 - centerY * viewport.scale
            )
        )
    }

    var canCopyCanvasNodes: Bool {
        !selectedNodeIDs.isEmpty
    }

    var hasCurrentCanvasNodeClipboard: Bool {
        guard canvasNodeClipboard != nil,
              let canvasNodeClipboardToken else { return false }
        return CanvasPasteboardReader.containsCanvasNodeToken(canvasNodeClipboardToken)
    }

    /// Copies a lightweight value snapshot of the selected canvas nodes.
    /// Image assets and analysis payloads are never placed on this clipboard;
    /// pasted image nodes keep referring to the existing `AssetID`.
    @discardableResult
    func copySelectedCanvasNodes() -> Bool {
        guard let payload = CanvasNodeCopyPayload(
            workspace: workspace,
            selectedNodeIDs: selectedNodeIDs
        ) else { return false }

        canvasNodeClipboard = payload
        canvasNodePasteCount = 0
        let clipboardToken = UUID().uuidString
        canvasNodeClipboardToken = clipboardToken
        guard CanvasPasteboardReader.replaceContents(withCanvasNodeToken: clipboardToken) else {
            canvasNodeClipboard = nil
            canvasNodeClipboardToken = nil
            statusMessage = nil
            errorMessage = "无法写入系统剪贴板。"
            return false
        }
        statusMessage = payload.nodeCount == 1
            ? "已复制 1 个画布节点"
            : "已复制 \(payload.nodeCount) 个画布节点"
        return true
    }

    /// Pastes a new independent node group with a consistent 32pt view-space
    /// cascade. A single undo snapshot covers every cloned node and relation.
    @discardableResult
    func pasteCopiedCanvasNodes() -> [CanvasNodeID] {
        guard isReady,
              hasCurrentCanvasNodeClipboard,
              activeAnalysisAssetIDs.isEmpty,
              activeGenerationGeneratorIDs.isEmpty,
              let payload = canvasNodeClipboard,
              viewport.scale > 0 else { return [] }

        recordUndoSnapshot()
        canvasNodePasteCount += 1
        let viewOffset = 32 * Double(canvasNodePasteCount)
        let worldOffset = viewOffset / viewport.scale
        let primarySourceNodeID = primarySelectedNodeID.flatMap { selectedID in
            payload.nodes.contains(where: { $0.id == selectedID }) ? selectedID : nil
        }
        let result = payload.paste(
            into: &workspace,
            offset: WorldSize(width: worldOffset, height: worldOffset)
        )
        let pastedNodeIDs = Set(result.nodeIDs)
        setSelection(
            pastedNodeIDs,
            preferredPrimary: primarySourceNodeID.flatMap { result.nodeIDMap[$0] }
        )
        statusMessage = result.nodes.count == 1
            ? "已粘贴 1 个画布节点"
            : "已粘贴 \(result.nodes.count) 个画布节点，并保留组内关系"
        scheduleSave()
        return result.nodeIDs
    }

    func clearSelection() {
        primarySelectedNodeID = nil
        selectedNodeIDs.removeAll()
    }

    func panBy(x: Double, y: Double) {
        viewport = viewport.pannedBy(x: x, y: y)
    }

    func zoom(by factor: Double, viewportSize: ViewSize) {
        let anchor = ViewPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        zoom(by: factor, around: anchor)
    }

    func zoom(by factor: Double, around anchor: ViewPoint) {
        viewport = viewport.zoomed(
            by: factor,
            around: anchor,
            limitedTo: minimumScale ... maximumScale
        )
    }

    func resetViewport(viewportSize: ViewSize) {
        viewport = ViewportTransform(
            scale: 1,
            translation: ViewPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        )
    }

    func moveCanvasNode(id: CanvasNodeID, to origin: WorldPoint) {
        guard let index = workspace.canvasNodes.firstIndex(where: { $0.id == id }) else { return }
        recordUndoSnapshot()
        workspace.canvasNodes[index].frame.origin = origin
        setSelection([id], preferredPrimary: id)
        scheduleSave()
    }

    func applyCanvasNodeGroupMove(_ command: CanvasNodeGroupMoveCommand) {
        guard !command.isNoOp,
              command.moves.contains(where: { move in
                  workspace.canvasNodes.contains { $0.id == move.nodeID }
              }) else { return }
        recordUndoSnapshot()
        let movedCount = command.apply(to: &workspace.canvasNodes)
        if movedCount > 1 {
            statusMessage = "已移动 \(movedCount) 个节点"
        }
        scheduleSave()
    }

    func applyCanvasNodeResize(_ command: CanvasNodeResizeCommand) {
        guard !command.isNoOp,
              let index = workspace.canvasNodes.firstIndex(where: { $0.id == command.nodeID }),
              workspace.canvasNodes[index].frame == command.fromFrame else { return }
        recordUndoSnapshot()
        workspace.canvasNodes[index].frame = command.toFrame
        setSelection([command.nodeID], preferredPrimary: command.nodeID)
        scheduleSave()
    }

    /// Content changes may increase a node's intrinsic minimum, but never take
    /// space away from a size the user chose manually.
    func ensureCanvasNodeMinimumSize(nodeID: CanvasNodeID, minimumSize: WorldSize) {
        guard minimumSize.width.isFinite, minimumSize.height.isFinite,
              let index = workspace.canvasNodes.firstIndex(where: { $0.id == nodeID }) else {
            return
        }
        let current = workspace.canvasNodes[index].frame.size
        let target = WorldSize(
            width: max(current.width, minimumSize.width),
            height: max(current.height, minimumSize.height)
        )
        guard target != current else { return }
        workspace.canvasNodes[index].frame.size = target
        scheduleSave()
    }

    /// Nodes no longer expose manual resizing, so the generator can follow its
    /// intrinsic content height instead of preserving stale oversized frames.
    func fitCanvasNodeHeight(nodeID: CanvasNodeID, height: Double) {
        guard height.isFinite, height > 0,
              let index = workspace.canvasNodes.firstIndex(where: { $0.id == nodeID }) else {
            return
        }
        let currentHeight = workspace.canvasNodes[index].frame.height
        guard abs(currentHeight - height) > 0.5 else { return }
        workspace.canvasNodes[index].frame.size.height = height
        scheduleSave()
    }

    func selectGenerationGroup(_ groupID: CanvasGenerationGroupID) {
        guard let group = generationGroup(id: groupID),
              let primaryNodeID = group.memberNodeIDs.first else { return }
        setSelection(Set(group.memberNodeIDs), preferredPrimary: primaryNodeID)
    }

    func expandingCollapsedGenerationGroupSelection(
        _ nodeIDs: Set<CanvasNodeID>
    ) -> Set<CanvasNodeID> {
        var result = nodeIDs
        for group in workspace.generationGroups where group.isCollapsed {
            guard !result.isDisjoint(with: group.memberNodeIDs) else { continue }
            result.formUnion(group.memberNodeIDs)
        }
        return result
    }

    func toggleGenerationGroup(_ groupID: CanvasGenerationGroupID) {
        guard let index = workspace.generationGroups.firstIndex(where: { $0.id == groupID }) else {
            return
        }
        recordUndoSnapshot()
        workspace.generationGroups[index].isCollapsed.toggle()
        workspace.generationGroups[index].updatedAt = .now
        selectGenerationGroup(groupID)
        statusMessage = workspace.generationGroups[index].isCollapsed
            ? "已折叠生成结果"
            : "已展开生成结果"
        saveImmediately()
    }

    func moveGenerationGroup(
        id groupID: CanvasGenerationGroupID,
        byWorldTranslation translation: WorldSize
    ) {
        guard translation.width.isFinite,
              translation.height.isFinite,
              (abs(translation.width) > 0.001 || abs(translation.height) > 0.001),
              let groupIndex = workspace.generationGroups.firstIndex(where: { $0.id == groupID })
        else { return }

        recordUndoSnapshot()
        workspace.generationGroups[groupIndex].origin = WorldPoint(
            x: workspace.generationGroups[groupIndex].origin.x + translation.width,
            y: workspace.generationGroups[groupIndex].origin.y + translation.height
        )
        workspace.generationGroups[groupIndex].updatedAt = .now
        let memberIDs = Set(workspace.generationGroups[groupIndex].memberNodeIDs)
        for nodeIndex in workspace.canvasNodes.indices where memberIDs.contains(workspace.canvasNodes[nodeIndex].id) {
            workspace.canvasNodes[nodeIndex].frame.origin = WorldPoint(
                x: workspace.canvasNodes[nodeIndex].frame.origin.x + translation.width,
                y: workspace.canvasNodes[nodeIndex].frame.origin.y + translation.height
            )
        }
        selectGenerationGroup(groupID)
        scheduleSave()
    }

    /// Turns one generated result occurrence into an independent source image.
    /// The generated asset and its history remain untouched; the source alias
    /// reuses the same stored image file and only adds lightweight metadata.
    func extractGeneratedResultAsSource(
        nodeID: CanvasNodeID,
        from requestedGroupID: CanvasGenerationGroupID? = nil,
        byWorldTranslation translation: WorldSize? = nil
    ) {
        guard let nodeIndex = workspace.canvasNodes.firstIndex(where: { $0.id == nodeID }),
              let assetID = workspace.canvasNodes[nodeIndex].imageAssetID,
              let generatedAsset = asset(for: assetID),
              generatedAsset.kind == .generated,
              generatedAsset.isStillImage else { return }

        let containingGroupID = generationGroup(containing: nodeID)?.id
        if let requestedGroupID, requestedGroupID != containingGroupID { return }

        let resolvedTranslation: WorldSize = {
            if let translation,
               translation.width.isFinite,
               translation.height.isFinite {
                return translation
            }
            guard let containingGroupID,
                  let group = generationGroup(id: containingGroupID) else {
                return .zero
            }
            let groupBounds = generationGroupLayout(for: group).bounds
            return WorldSize(
                width: groupBounds.maxX + placementPolicy.cascadeOffset.width
                    - workspace.canvasNodes[nodeIndex].frame.minX,
                height: 0
            )
        }()

        recordUndoSnapshot()
        let sourceAsset = generatedAsset.sourceMaterialAlias()
        workspace.assets.append(sourceAsset)
        workspace.canvasNodes[nodeIndex].entityID = sourceAsset.id.rawValue
        workspace.canvasNodes[nodeIndex].frame.origin = WorldPoint(
            x: workspace.canvasNodes[nodeIndex].frame.origin.x + resolvedTranslation.width,
            y: workspace.canvasNodes[nodeIndex].frame.origin.y + resolvedTranslation.height
        )
        workspace.canvasNodes[nodeIndex].zIndex =
            (workspace.canvasNodes.map(\.zIndex).max() ?? -1) + 1

        if let containingGroupID,
           let groupIndex = workspace.generationGroups.firstIndex(
               where: { $0.id == containingGroupID }
           ) {
            workspace.generationGroups[groupIndex].memberNodeIDs.removeAll { $0 == nodeID }
            workspace.generationGroups[groupIndex].updatedAt = .now
            if workspace.generationGroups[groupIndex].memberNodeIDs.isEmpty {
                workspace.generationGroups.remove(at: groupIndex)
            } else {
                reflowGenerationGroup(at: groupIndex)
            }
        }

        setSelection([nodeID], preferredPrimary: nodeID)
        selectedLibraryAssetID = sourceAsset.id
        statusMessage = "已提取为普通图片素材；原生成记录仍然保留"
        saveImmediately()
    }

    func removeGenerationGroupFromCanvas(_ groupID: CanvasGenerationGroupID) {
        guard let group = generationGroup(id: groupID) else { return }
        let memberIDs = Set(group.memberNodeIDs)
        recordUndoSnapshot()
        workspace.canvasNodes.removeAll { memberIDs.contains($0.id) }
        workspace.generationGroups.removeAll { $0.id == groupID }
        setSelection(selectedNodeIDs.subtracting(memberIDs))
        statusMessage = "已从画布移除结果组；素材和生成历史仍保留"
        saveImmediately()
    }

    func organizeExistingGenerationResults(generatorID: GeneratorID) {
        let existingMemberIDs = Set(workspace.generationGroups.flatMap(\.memberNodeIDs))
        let generationIDs = Set(
            workspace.generations
                .filter { $0.generatorID == generatorID }
                .map(\.id)
        )
        let candidateNodes = workspace.canvasNodes.filter { node in
            guard !existingMemberIDs.contains(node.id),
                  let assetID = node.imageAssetID,
                  let asset = asset(for: assetID),
                  asset.kind == .generated,
                  let sourceGenerationID = asset.sourceGenerationID else { return false }
            return generationIDs.contains(sourceGenerationID)
        }
        guard !candidateNodes.isEmpty else {
            statusMessage = generationGroup(for: generatorID) == nil
                ? "这个生图节点暂无可整理的画布结果"
                : "现有结果已全部在结果组中"
            return
        }

        recordUndoSnapshot()
        let preferredOrigin: WorldPoint
        if let first = candidateNodes.first {
            let minX = candidateNodes.map(\.frame.minX).min() ?? first.frame.minX
            let minY = candidateNodes.map(\.frame.minY).min() ?? first.frame.minY
            preferredOrigin = WorldPoint(x: minX - 24, y: minY - 84)
        } else {
            preferredOrigin = .zero
        }
        guard let groupID = appendGenerationResults(
            candidateNodes.map(\.id),
            to: generatorID,
            preferredOrigin: preferredOrigin
        ) else { return }
        selectGenerationGroup(groupID)
        statusMessage = "已将 \(candidateNodes.count) 个现有结果整理成一组"
        saveImmediately()
    }

    func removeSelectedNodeFromCanvas() {
        removeSelectedNodesFromCanvas()
    }

    func removeSelectedNodesFromCanvas() {
        guard !selectedNodeIDs.isEmpty else { return }
        let selectedActiveGeneratorIDs = Set<GeneratorID>(
            workspace.canvasNodes.compactMap { node in
                guard selectedNodeIDs.contains(node.id),
                      let generatorID = node.generatorID,
                      activeGenerationGeneratorIDs.contains(generatorID) else { return nil }
                return generatorID
            }
        )
        guard selectedActiveGeneratorIDs.isEmpty else {
            statusMessage = "图片生成任务正在运行，请先取消任务再删除这个图片生成节点"
            return
        }
        let removableIDs = selectedNodeIDs
        let removedCount = workspace.canvasNodes.lazy.filter { removableIDs.contains($0.id) }.count
        guard removedCount > 0 else { return }
        recordUndoSnapshot()
        let result = CanvasNodeRemovalPolicy.remove(
            nodeIDs: removableIDs,
            from: &workspace
        )
        pruneGenerationGroupsAfterNodeRemoval()
        clearSelection()
        if !result.removedGeneratorIDs.isEmpty,
           !result.removedPromptModuleIDs.isEmpty {
            statusMessage = "已删除选中的工作流组件；素材、生成历史和结果图片继续保留"
        } else if !result.removedGeneratorIDs.isEmpty {
            statusMessage = result.removedGeneratorIDs.count == 1
                ? "已删除生图节点与配置；生成历史和结果图片继续保留"
                : "已删除 \(result.removedGeneratorIDs.count) 个生图节点与配置；生成历史和结果图片继续保留"
        } else if !result.removedPromptModuleIDs.isEmpty {
            statusMessage = result.removedPromptModuleIDs.count == 1
                ? "已删除手写提示词及其连接"
                : "已删除 \(result.removedPromptModuleIDs.count) 个手写提示词及其连接"
        } else {
            statusMessage = removedCount == 1
                ? "已从画布移除实例；素材或提示词仍保留在工作区"
                : "已从画布移除 \(removedCount) 个实例；底层内容仍保留在工作区"
        }
        saveImmediately()
    }

    func removeCanvasNode(id: CanvasNodeID) {
        guard let node = workspace.canvasNodes.first(where: { $0.id == id }) else { return }
        if let generatorID = node.generatorID,
           activeGenerationGeneratorIDs.contains(generatorID) {
            statusMessage = "图片生成任务正在运行，请先取消任务再删除这个图片生成节点"
            return
        }
        recordUndoSnapshot()
        let result = CanvasNodeRemovalPolicy.remove(nodeIDs: [id], from: &workspace)
        pruneGenerationGroupsAfterNodeRemoval()
        if selectedNodeIDs.contains(id) {
            selectedNodeIDs.remove(id)
            if primarySelectedNodeID == id {
                primarySelectedNodeID = topmostSelectedNodeID()
            }
        }
        if !result.removedGeneratorIDs.isEmpty {
            statusMessage = "已删除生图节点与配置；生成历史和结果图片继续保留"
        } else if !result.removedPromptModuleIDs.isEmpty {
            statusMessage = "已删除手写提示词及其连接"
        } else {
            statusMessage = "已从画布移除实例；底层内容仍保留在工作区"
        }
        saveImmediately()
    }

    func revealAssetInFinder(_ assetID: AssetID) {
        guard let asset = asset(for: assetID) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([assetURL(for: asset)])
    }

    func undo() {
        guard activeAnalysisAssetIDs.isEmpty, activeGenerationGeneratorIDs.isEmpty,
              let previous = undoStack.popLast() else { return }
        redoStack.append(workspace)
        workspace = previous
        clearSelection()
        statusMessage = "已撤销上一步操作"
        updateHistoryDepths()
        scheduleSave()
    }

    func redo() {
        guard activeAnalysisAssetIDs.isEmpty, activeGenerationGeneratorIDs.isEmpty,
              let next = redoStack.popLast() else { return }
        undoStack.append(workspace)
        workspace = next
        clearSelection()
        statusMessage = "已重做上一步操作"
        updateHistoryDepths()
        scheduleSave()
    }

    private func topmostSelectedNodeID() -> CanvasNodeID? {
        workspace.canvasNodes
            .filter { selectedNodeIDs.contains($0.id) }
            .max { lhs, rhs in
                if lhs.zIndex != rhs.zIndex { return lhs.zIndex < rhs.zIndex }
                return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
            }?
            .id
    }

    /// Keeps legacy and pasted generator nodes large enough for the current
    /// sectioned control layout without moving or shrinking user-arranged nodes.
    private func normalizeGeneratorNodeMinimumHeights() -> Bool {
        var didChange = false
        for index in workspace.canvasNodes.indices
            where workspace.canvasNodes[index].kind == .generation {
            let currentHeight = workspace.canvasNodes[index].frame.height
            let normalizedHeight = GeneratorNodeLayoutPolicy.normalizedHeight(currentHeight)
            guard abs(currentHeight - normalizedHeight) > 0.5 else { continue }
            workspace.canvasNodes[index].frame.size.height = normalizedHeight
            didChange = true
        }
        return didChange
    }

    /// Moves the former recipe-level final prompt into the generator-owned
    /// editor once. Runtime compilation must not fall back to the legacy value,
    /// otherwise clearing the editor would make the old prompt reappear.
    private func migrateLegacyGeneratorPromptOverrides() -> Bool {
        var migratedRecipeIDs = Set<RecipeID>()
        var didChange = false

        for generatorIndex in workspace.generators.indices {
            guard workspace.generators[generatorIndex].promptText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty,
                let recipeIndex = workspace.recipes.firstIndex(where: {
                    $0.id == workspace.generators[generatorIndex].recipeID
                }),
                let legacyOverride = workspace.recipes[recipeIndex].promptOverride,
                !legacyOverride.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            workspace.generators[generatorIndex].promptText = legacyOverride.text
            workspace.generators[generatorIndex].revision += 1
            workspace.generators[generatorIndex].updatedAt = .now
            migratedRecipeIDs.insert(workspace.recipes[recipeIndex].id)
            didChange = true
        }

        for recipeIndex in workspace.recipes.indices
            where migratedRecipeIDs.contains(workspace.recipes[recipeIndex].id) {
            workspace.recipes[recipeIndex].promptOverride = nil
            workspace.recipes[recipeIndex].revision += 1
            workspace.recipes[recipeIndex].updatedAt = .now
        }

        if didChange {
            workspace.updatedAt = .now
        }
        return didChange
    }

    @discardableResult
    private func appendGenerationResults(
        _ nodeIDs: [CanvasNodeID],
        to generatorID: GeneratorID,
        preferredOrigin: WorldPoint
    ) -> CanvasGenerationGroupID? {
        let validNodeIDs = Set(workspace.canvasNodes.map(\.id))
        let existingMemberIDs = Set(workspace.generationGroups.flatMap(\.memberNodeIDs))
        let appendableNodeIDs = nodeIDs.filter {
            validNodeIDs.contains($0) && !existingMemberIDs.contains($0)
        }
        guard !appendableNodeIDs.isEmpty else {
            return generationGroup(for: generatorID)?.id
        }

        let groupIndex: Int
        if let existingIndex = workspace.generationGroups.firstIndex(
            where: { $0.generatorID == generatorID }
        ) {
            groupIndex = existingIndex
            workspace.generationGroups[groupIndex].memberNodeIDs.append(contentsOf: appendableNodeIDs)
            workspace.generationGroups[groupIndex].updatedAt = .now
        } else {
            workspace.generationGroups.append(
                CanvasGenerationGroup(
                    generatorID: generatorID,
                    name: WorkspaceDisplayNamePolicy.nextDefaultName(
                        for: .generationGroup,
                        existingNames: workspace.generationGroups.compactMap(\.name)
                    ),
                    memberNodeIDs: appendableNodeIDs,
                    origin: preferredOrigin
                )
            )
            groupIndex = workspace.generationGroups.index(before: workspace.generationGroups.endIndex)
        }
        reflowGenerationGroup(at: groupIndex)
        return workspace.generationGroups[groupIndex].id
    }

    private func reflowGenerationGroup(at groupIndex: Int) {
        guard workspace.generationGroups.indices.contains(groupIndex) else { return }
        let group = workspace.generationGroups[groupIndex]
        let expandedLayout = generationGroupLayout.layout(
            members: generationGroupMembers(group),
            origin: group.origin,
            columns: group.columns,
            isCollapsed: false
        )
        let framesByNodeID = Dictionary(
            uniqueKeysWithValues: expandedLayout.memberPlacements.map { ($0.nodeID, $0.frame) }
        )
        for nodeIndex in workspace.canvasNodes.indices {
            guard let frame = framesByNodeID[workspace.canvasNodes[nodeIndex].id] else { continue }
            workspace.canvasNodes[nodeIndex].frame = frame
        }
    }

    @discardableResult
    private func repairGenerationGroups() -> Bool {
        let originalGroups = workspace.generationGroups
        let assetsByID = Dictionary(uniqueKeysWithValues: workspace.assets.map { ($0.id, $0) })
        let nodesByID = Dictionary(uniqueKeysWithValues: workspace.canvasNodes.map { ($0.id, $0) })
        let liveGeneratorIDs = Set(workspace.generators.map(\.id))
        var claimedNodeIDs = Set<CanvasNodeID>()
        var normalizedGroups: [CanvasGenerationGroup] = []

        for sourceGroup in originalGroups {
            let members = sourceGroup.memberNodeIDs.filter { nodeID in
                guard claimedNodeIDs.insert(nodeID).inserted,
                      let node = nodesByID[nodeID],
                      let assetID = node.imageAssetID,
                      assetsByID[assetID]?.kind == .generated else { return false }
                return true
            }
            guard !members.isEmpty else { continue }

            var group = sourceGroup
            if let generatorID = group.generatorID,
               !liveGeneratorIDs.contains(generatorID) {
                group.generatorID = nil
                group.updatedAt = .now
            }
            group.memberNodeIDs = members
            group.columns = max(1, group.columns)
            normalizedGroups.append(group)
        }

        workspace.generationGroups = normalizedGroups
        for index in workspace.generationGroups.indices {
            reflowGenerationGroup(at: index)
        }
        let didChange = workspace.generationGroups != originalGroups
            || workspace.generationGroups.contains { group in
                let expectedFrames = generationGroupLayout.layout(
                    members: generationGroupMembers(group),
                    origin: group.origin,
                    columns: group.columns,
                    isCollapsed: false
                ).memberFrames
                return expectedFrames.contains { nodeID, frame in
                    nodesByID[nodeID]?.frame != frame
                }
            }
        if didChange { workspace.updatedAt = .now }
        return didChange
    }

    @discardableResult
    private func repairGenerationHistoryMetadata() -> Bool {
        let generatorsByID = Dictionary(
            uniqueKeysWithValues: workspace.generators.map { ($0.id, $0) }
        )
        let promptsByID = Dictionary(
            uniqueKeysWithValues: workspace.compiledPrompts.map { ($0.id, $0) }
        )
        let recipesByID = Dictionary(
            uniqueKeysWithValues: workspace.recipes.map { ($0.id, $0) }
        )
        var didChange = false

        for generationIndex in workspace.generations.indices {
            let generator = workspace.generations[generationIndex].generatorID
                .flatMap { generatorsByID[$0] }
            let prompt = promptsByID[workspace.generations[generationIndex].promptSnapshotID]
            let recipe = recipesByID[workspace.generations[generationIndex].recipeID]
            let generatorNameSnapshot =
                workspace.generations[generationIndex].generatorNameSnapshot

            if generatorNameSnapshot == nil,
               let generator {
                workspace.generations[generationIndex].generatorNameSnapshot = generator.name
                didChange = true
            }

            let currentTitle = workspace.generations[generationIndex].displayTitle?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if currentTitle.isEmpty {
                workspace.generations[generationIndex].displayTitle =
                    GenerationHistoryTitlePolicy.baseTitle(
                        generatorName: generatorNameSnapshot ?? generator?.name,
                        compiledPrompt: prompt,
                        recipe: recipe
                    )
                didChange = true
            }
        }

        let generationsByID = Dictionary(
            uniqueKeysWithValues: workspace.generations.map { ($0.id, $0) }
        )
        for assetIndex in workspace.assets.indices {
            guard workspace.assets[assetIndex].kind == .generated,
                  workspace.assets[assetIndex].displayName.hasPrefix("generation-"),
                  let generationID = workspace.assets[assetIndex].sourceGenerationID,
                  let generation = generationsByID[generationID],
                  let title = generation.displayTitle,
                  !title.isEmpty,
                  let outputIndex = generation.outputAssetIDs.firstIndex(
                    of: workspace.assets[assetIndex].id
                  ) else {
                continue
            }
            workspace.assets[assetIndex].displayName = generation.outputAssetIDs.count == 1
                ? title
                : "\(title) \(outputIndex + 1)"
            didChange = true
        }

        if didChange {
            workspace.updatedAt = .now
        }
        return didChange
    }

    @discardableResult
    private func repairWorkspaceDisplayNames() -> Bool {
        var didChange = false

        var recipeNames: [String] = []
        for index in workspace.recipes.indices {
            let current = WorkspaceDisplayNamePolicy.normalized(workspace.recipes[index].name)
            let needsReplacement = current.isEmpty
                || (WorkspaceDisplayNamePolicy.isDefaultName(current, for: .recipe)
                    && recipeNames.contains(current))
            let repaired = needsReplacement
                ? WorkspaceDisplayNamePolicy.nextDefaultName(
                    for: .recipe,
                    existingNames: recipeNames
                )
                : current
            if workspace.recipes[index].name != repaired {
                workspace.recipes[index].name = repaired
                workspace.recipes[index].updatedAt = .now
                didChange = true
            }
            recipeNames.append(repaired)
        }

        var generatorNames: [String] = []
        for index in workspace.generators.indices {
            let current = WorkspaceDisplayNamePolicy.normalized(workspace.generators[index].name)
            let needsReplacement = current.isEmpty
                || (WorkspaceDisplayNamePolicy.isDefaultName(current, for: .generator)
                    && generatorNames.contains(current))
            let repaired = needsReplacement
                ? WorkspaceDisplayNamePolicy.nextDefaultName(
                    for: .generator,
                    existingNames: generatorNames
                )
                : current
            if workspace.generators[index].name != repaired {
                workspace.generators[index].name = repaired
                workspace.generators[index].updatedAt = .now
                didChange = true
            }
            generatorNames.append(repaired)
        }

        var groupNames: [String] = []
        for index in workspace.generationGroups.indices {
            let current = WorkspaceDisplayNamePolicy.normalized(
                workspace.generationGroups[index].name ?? ""
            )
            let needsReplacement = current.isEmpty
                || (WorkspaceDisplayNamePolicy.isDefaultName(current, for: .generationGroup)
                    && groupNames.contains(current))
            let repaired = needsReplacement
                ? WorkspaceDisplayNamePolicy.nextDefaultName(
                    for: .generationGroup,
                    existingNames: groupNames
                )
                : current
            if workspace.generationGroups[index].name != repaired {
                workspace.generationGroups[index].name = repaired
                workspace.generationGroups[index].updatedAt = .now
                didChange = true
            }
            groupNames.append(repaired)
        }

        if didChange { workspace.updatedAt = .now }
        return didChange
    }

    private func pruneGenerationGroupsAfterNodeRemoval() {
        let validNodeIDs = Set(workspace.canvasNodes.map(\.id))
        for index in workspace.generationGroups.indices {
            workspace.generationGroups[index].memberNodeIDs.removeAll {
                !validNodeIDs.contains($0)
            }
        }
        workspace.generationGroups.removeAll { $0.memberNodeIDs.isEmpty }
        for index in workspace.generationGroups.indices {
            reflowGenerationGroup(at: index)
        }
    }

    private func centeredOrigin(for kind: CanvasNodeKind, viewportSize: ViewSize) -> WorldPoint {
        centeredOrigin(
            for: placementPolicy.defaultSize(for: kind),
            viewportSize: viewportSize
        )
    }

    private func centeredOrigin(for size: WorldSize, viewportSize: ViewSize) -> WorldPoint {
        let visibleRect = viewport.visibleWorldRect(viewportSize: viewportSize)
        return WorldPoint(
            x: visibleRect.minX + (visibleRect.width - size.width) / 2,
            y: visibleRect.minY + (visibleRect.height - size.height) / 2
        )
    }

    private func imageNodeSize(for asset: Asset) -> WorldSize {
        guard asset.kind == .generated else { return placementPolicy.imageSize }
        return generatedImagePlacement.size(for: asset.pixelSize)
    }

    private func sourceAssetAspectRatio(_ asset: Asset) -> String {
        guard let ratio = asset.contentAspectRatio else { return "16:9" }
        let supported = ImageGenerationModelCatalog.model(
            providerID: defaultGenerationTarget.providerID,
            modelID: defaultGenerationTarget.modelID
        )?.supportedAspectRatios ?? ["16:9"]
        return supported.min { lhs, rhs in
            abs(aspectRatioValue(lhs) - ratio) < abs(aspectRatioValue(rhs) - ratio)
        } ?? "16:9"
    }

    private func aspectRatioValue(_ value: String) -> Double {
        let parts = value.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2, parts[1] > 0 else { return 1 }
        return parts[0] / parts[1]
    }

    private func availableImageInsertionOrigin(centeredAt origin: WorldPoint) -> WorldPoint {
        var candidate = origin
        let occupiedOrigins = Set(workspace.canvasNodes.map { $0.frame.standardized.origin })
        while occupiedOrigins.contains(candidate) {
            candidate = WorldPoint(
                x: candidate.x + placementPolicy.cascadeOffset.width,
                y: candidate.y + placementPolicy.cascadeOffset.height
            )
        }
        return candidate
    }

    private func referenceInputs(for generator: Generator) async throws -> [ProviderMediaInput] {
        var result: [ProviderMediaInput] = []
        var resultIndexByAssetID: [AssetID: Int] = [:]
        for binding in generator.assetBindings.filter(\.isEnabled).sorted(by: { $0.order < $1.order }) {
            if let resultIndex = resultIndexByAssetID[binding.assetID] {
                if !result[resultIndex].referenceRoles.contains(binding.role) {
                    result[resultIndex].referenceRoles.append(binding.role)
                }
                continue
            }
            guard let asset = asset(for: binding.assetID), asset.supportsMediaReference else {
                throw GeminiProviderError.invalidConfiguration("参考素材不存在或类型不受支持")
            }
            let source: ProviderMediaSource
            if asset.isVideo {
                source = .managedFile(try await resolvedAssetURL(for: asset))
            } else {
                source = .inline(
                    try await repository.readAssetData(
                        relativePath: asset.relativePath,
                        from: packageURL
                    )
                )
            }
            resultIndexByAssetID[binding.assetID] = result.count
            result.append(
                ProviderMediaInput(
                    source: source,
                    mimeType: asset.mimeType,
                    mediaKind: asset.mediaKind,
                    referenceRoles: [binding.role]
                )
            )
        }
        return result
    }

    private func imageEditInput(for generator: Generator) async throws -> ImageEditInput? {
        guard let edit = generator.imageEdit else { return nil }
        guard generator.mediaKind == .image,
              let sourceAsset = asset(for: edit.sourceAssetID),
              sourceAsset.isStillImage else {
            throw GeminiProviderError.invalidConfiguration("局部改图原图")
        }
        let sourceData = try await repository.readAssetData(
            relativePath: sourceAsset.relativePath,
            from: packageURL
        )
        let maskData = try await repository.readMaskArtifact(
            relativePath: edit.maskRelativePath,
            from: packageURL
        )
        return ImageEditInput(
            source: ProviderMediaInput(
                source: .inline(sourceData),
                mimeType: sourceAsset.mimeType,
                mediaKind: .image
            ),
            mask: ProviderMediaInput(
                source: .inline(maskData),
                mimeType: "image/png",
                mediaKind: .image
            )
        )
    }

    private func finishJob(id: JobID, state: JobState, message: String?) {
        guard let index = workspace.jobs.firstIndex(where: { $0.id == id }) else { return }
        workspace.jobs[index].state = state
        workspace.jobs[index].message = message
        workspace.jobs[index].updatedAt = .now
    }

    private func recoverInterruptedJobs() -> Bool {
        var changed = false
        for index in workspace.jobs.indices where [.queued, .running].contains(workspace.jobs[index].state) {
            workspace.jobs[index].state = .failed
            workspace.jobs[index].message = "App 在任务完成前退出"
            workspace.jobs[index].updatedAt = .now
            changed = true
        }
        for index in workspace.assets.indices where workspace.assets[index].state == .analyzing {
            workspace.assets[index].state = .failed
            changed = true
        }
        for index in workspace.generations.indices where [.queued, .generating].contains(workspace.generations[index].state) {
            workspace.generations[index].state = .failed
            changed = true
        }
        if changed { workspace.updatedAt = .now }
        return changed
    }

    private func recordUndoSnapshot() {
        undoStack.append(workspace)
        if undoStack.count > 30 {
            undoStack.removeFirst(undoStack.count - 30)
        }
        redoStack.removeAll()
        updateHistoryDepths()
    }

    private func updateHistoryDepths() {
        undoDepth = undoStack.count
        redoDepth = redoStack.count
    }

    private func scheduleSave() {
        pendingSaveTask?.cancel()
        let scheduledGeneration = saveGeneration
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self else { return }
            await self.persistWorkspace(expectedSaveGeneration: scheduledGeneration)
        }
    }

    private func saveImmediately() {
        pendingSaveTask?.cancel()
        let scheduledGeneration = saveGeneration
        pendingSaveTask = Task { [weak self] in
            guard let self else { return }
            await self.persistWorkspace(expectedSaveGeneration: scheduledGeneration)
        }
    }

    func flushPendingSave() async {
        invalidatePendingSave()
        await persistWorkspace()
    }

    func cloneProject(to destinationURL: URL) async throws -> Workspace {
        invalidatePendingSave()
        _ = try await saveCurrentWorkspace()

        var clone = workspace
        clone.id = WorkspaceID()
        clone.title = destinationURL.deletingPathExtension().lastPathComponent
        clone.createdAt = .now
        clone.updatedAt = clone.createdAt
        try await repository.clonePackage(
            from: packageURL,
            to: destinationURL,
            workspace: clone
        )
        return clone
    }

    func finalizeDraftProject(to destinationURL: URL) async throws -> Workspace {
        guard !hasActiveFileProducingTasks else {
            throw CocoaError(
                .fileWriteUnknown,
                userInfo: [NSLocalizedDescriptionKey: "仍有素材导入、图片分析或图片生成任务正在进行，请完成后再保存项目。"]
            )
        }
        invalidatePendingSave()
        _ = try await saveCurrentWorkspace()

        var savedWorkspace = workspace
        savedWorkspace.title = destinationURL.deletingPathExtension().lastPathComponent
        savedWorkspace.updatedAt = .now
        try await repository.clonePackage(
            from: packageURL,
            to: destinationURL,
            workspace: savedWorkspace
        )
        return savedWorkspace
    }

    func exportProjectCopy(to destinationURL: URL) async throws {
        invalidatePendingSave()
        _ = try await saveCurrentWorkspace()
        try await repository.clonePackage(
            from: packageURL,
            to: destinationURL,
            workspace: workspace
        )
        statusMessage = "项目副本已导出到“\(destinationURL.lastPathComponent)”"
    }

    private func invalidatePendingSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        saveGeneration &+= 1
    }

    @discardableResult
    private func saveCurrentWorkspace(
        expectedSaveGeneration: UInt64? = nil
    ) async throws -> Bool {
        guard expectedSaveGeneration == nil || expectedSaveGeneration == saveGeneration else {
            return false
        }
        workspace.updatedAt = .now
        let snapshot = workspace
        return try await manifestSaveCoordinator.save { [repository, packageURL] in
            try await repository.save(snapshot, to: packageURL)
        }
    }

    private func persistWorkspace(expectedSaveGeneration: UInt64? = nil) async {
        do {
            _ = try await saveCurrentWorkspace(expectedSaveGeneration: expectedSaveGeneration)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func hydrateAssetSizesAndNormalizeGeneratedFrames() async -> Bool {
        var didChange = false

        for assetIndex in workspace.assets.indices {
            if workspace.assets[assetIndex].isStillImage,
               workspace.assets[assetIndex].contentAspectRatio == nil,
               let pixelSize = try? await repository.readAssetPixelSize(
                   relativePath: workspace.assets[assetIndex].relativePath,
                   from: packageURL
               ) {
                workspace.assets[assetIndex].pixelSize = pixelSize
                didChange = true
            }

            // CanvasNode.frame is user-owned geometry. New generated nodes are
            // created at the natural ratio, but hydration must never overwrite
            // a size the user chose with an edge or corner resize gesture.
        }

        if didChange { workspace.updatedAt = .now }
        return didChange
    }

    private func registerImportedSourceAsset(
        _ result: OriginalAssetImportResult
    ) -> Asset {
        if let existingIndex = workspace.assets.firstIndex(where: { asset in
            if let contentHash = result.contentHash {
                return asset.contentHash == contentHash
            }
            return asset.relativePath == result.relativePath
        }) {
            if workspace.assets[existingIndex].contentAspectRatio == nil,
               let pixelSize = result.pixelSize {
                workspace.assets[existingIndex].pixelSize = pixelSize
            }
            return workspace.assets[existingIndex]
        }

        let asset = Asset(
            kind: .source,
            displayName: result.fileName,
            relativePath: result.relativePath,
            mimeType: result.mimeType,
            pixelSize: result.pixelSize,
            contentHash: result.contentHash
        )
        workspace.assets.append(asset)
        return asset
    }

    private static func defaultPackageURL() -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["IMAGE_LENS_WORKSPACE_PATH"],
           !overridePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: overridePath, isDirectory: true)
        }
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("Image Lens Studio", isDirectory: true)
            .appendingPathComponent("Default.imagelens", isDirectory: true)
    }
}

enum StudioSection: String, CaseIterable, Identifiable {
    case layers
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .layers: "图层"
        case .history: "运行记录"
        }
    }

    var systemImage: String {
        switch self {
        case .layers: "square.3.layers.3d"
        case .history: "clock.arrow.circlepath"
        }
    }
}
