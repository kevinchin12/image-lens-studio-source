import XCTest
@testable import ImageLensCore

final class WorkspaceRunProjectionTests: XCTestCase {
    func testGenerationAndItsJobMergeIntoOneRun() {
        let date = Date(timeIntervalSince1970: 100)
        let updated = Date(timeIntervalSince1970: 120)
        let recipeID = RecipeID()
        let promptID = CompiledPromptID()
        let generation = GenerationRecord(
            recipeID: recipeID,
            promptSnapshotID: promptID,
            providerID: ProviderID("gemini"),
            modelID: "image",
            aspectRatio: "1:1",
            state: .succeeded,
            outputAssetIDs: [AssetID()],
            createdAt: date
        )
        let job = JobRecord(
            kind: .generation,
            state: .succeeded,
            subjectID: generation.id.rawValue,
            message: "完成",
            createdAt: date,
            updatedAt: updated
        )
        let workspace = Workspace(
            title: "Test",
            generations: [generation],
            jobs: [job]
        )

        let runs = WorkspaceRunProjection.runs(in: workspace)

        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs[0].id, .generation(generation.id))
        XCTAssertEqual(runs[0].kind, .imageGeneration)
        XCTAssertEqual(runs[0].state, .succeeded)
        XCTAssertEqual(runs[0].outputAssetIDs, generation.outputAssetIDs)
        XCTAssertEqual(runs[0].message, "完成")
        XCTAssertEqual(runs[0].updatedAt, updated)
        XCTAssertEqual(runs[0].operationalJobID, job.id)
        XCTAssertEqual(runs[0].integrity, .consistent)
    }

    func testAnalysisAndOrphanGenerationJobsRemainVisible() {
        let analysis = JobRecord(
            kind: .analysis,
            state: .running,
            subjectID: UUID(),
            createdAt: Date(timeIntervalSince1970: 200),
            updatedAt: Date(timeIntervalSince1970: 210)
        )
        let orphan = JobRecord(
            kind: .generation,
            state: .failed,
            subjectID: UUID(),
            message: "失败",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 110)
        )
        let workspace = Workspace(title: "Test", jobs: [orphan, analysis])

        let runs = WorkspaceRunProjection.runs(in: workspace)

        XCTAssertEqual(runs.map(\.kind), [.imageAnalysis, .imageGeneration])
        XCTAssertEqual(runs.map(\.state), [.running, .failed])
        XCTAssertEqual(runs[1].message, "失败")
        XCTAssertEqual(runs[1].integrity, .orphanOperationalJob)
    }

    func testGenerationPartialStateIsPreserved() {
        let generation = GenerationRecord(
            recipeID: RecipeID(),
            promptSnapshotID: CompiledPromptID(),
            providerID: ProviderID("gemini"),
            modelID: "image",
            aspectRatio: "16:9",
            state: .partial,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let workspace = Workspace(title: "Test", generations: [generation])

        let run = WorkspaceRunProjection.runs(in: workspace).first
        XCTAssertEqual(run?.state, .partial)
        XCTAssertEqual(run?.integrity, .missingOperationalJob)
    }

    func testVideoGenerationProjectsAsVideoRun() {
        let generation = GenerationRecord(
            recipeID: RecipeID(),
            promptSnapshotID: CompiledPromptID(),
            providerID: ProviderID("video-provider"),
            modelID: "video-model",
            aspectRatio: "16:9",
            state: .succeeded,
            mediaKind: .video
        )
        let workspace = Workspace(title: "Video", generations: [generation])

        let run = WorkspaceRunProjection.userVisibleRuns(in: workspace).first

        XCTAssertEqual(run?.kind, .videoGeneration)
        XCTAssertEqual(run?.id, .generation(generation.id))
    }

    func testMismatchedStateAndDuplicateJobsRemainObservable() {
        let generation = GenerationRecord(
            recipeID: RecipeID(),
            promptSnapshotID: CompiledPromptID(),
            providerID: ProviderID("gemini"),
            modelID: "image",
            aspectRatio: "1:1",
            state: .succeeded,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let older = JobRecord(
            kind: .generation,
            state: .running,
            subjectID: generation.id.rawValue,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let newer = JobRecord(
            kind: .generation,
            state: .failed,
            subjectID: generation.id.rawValue,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 3)
        )
        let workspace = Workspace(
            title: "Test",
            generations: [generation],
            jobs: [older, newer]
        )

        let runs = WorkspaceRunProjection.runs(in: workspace)

        XCTAssertEqual(runs.count, 2)
        let canonical = runs.first { $0.id == .generation(generation.id) }
        XCTAssertEqual(canonical?.operationalJobID, newer.id)
        XCTAssertEqual(canonical?.integrity, .stateMismatch)
        let duplicate = runs.first { $0.id == .job(older.id) }
        XCTAssertEqual(duplicate?.integrity, .orphanOperationalJob)
    }

    func testUserVisibleRunsKeepAnalysisAndCanonicalGenerationOnly() {
        let date = Date(timeIntervalSince1970: 100)
        let generation = GenerationRecord(
            recipeID: RecipeID(),
            promptSnapshotID: CompiledPromptID(),
            providerID: ProviderID("gemini"),
            modelID: "image",
            aspectRatio: "1:1",
            state: .succeeded,
            createdAt: date
        )
        let generationJob = JobRecord(
            kind: .generation,
            state: .succeeded,
            subjectID: generation.id.rawValue,
            createdAt: date,
            updatedAt: date
        )
        let analysis = JobRecord(
            kind: .analysis,
            state: .succeeded,
            subjectID: UUID(),
            createdAt: date,
            updatedAt: date
        )
        let thumbnail = JobRecord(
            kind: .thumbnail,
            state: .succeeded,
            subjectID: UUID(),
            createdAt: date,
            updatedAt: date
        )
        let orphanGeneration = JobRecord(
            kind: .generation,
            state: .failed,
            subjectID: UUID(),
            createdAt: date,
            updatedAt: date
        )
        let workspace = Workspace(
            title: "Test",
            generations: [generation],
            jobs: [thumbnail, orphanGeneration, analysis, generationJob]
        )

        let visible = WorkspaceRunProjection.userVisibleRuns(in: workspace)

        XCTAssertEqual(Set(visible.map(\.id)), [
            .job(analysis.id),
            .generation(generation.id)
        ])
        XCTAssertEqual(
            visible.map(\.id),
            visible.sorted { $0.id.stableSortKey < $1.id.stableSortKey }.map(\.id)
        )
    }
}
