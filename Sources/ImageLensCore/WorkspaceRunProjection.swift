import Foundation

/// Generic operation vocabulary used by the workbench task and history layers.
/// Existing generation and job records remain the persisted sources of truth.
public enum WorkspaceRunKind: String, CaseIterable, Codable, Sendable {
    case imageAnalysis
    case imageGeneration
    case videoGeneration
    case thumbnail
}

public enum WorkspaceRunState: String, CaseIterable, Codable, Sendable {
    case queued
    case running
    case partial
    case succeeded
    case failed
    case cancelled
}

public enum WorkspaceRunID: Hashable, Sendable {
    case generation(GenerationID)
    case job(JobID)

    public var stableSortKey: String {
        switch self {
        case .generation(let id): "generation-\(id.rawValue.uuidString.lowercased())"
        case .job(let id): "job-\(id.rawValue.uuidString.lowercased())"
        }
    }
}

public enum WorkspaceRunSubject: Equatable, Sendable {
    case asset(AssetID)
    case generation(GenerationID)
    case opaque(UUID)

    public var rawValue: UUID {
        switch self {
        case .asset(let id): id.rawValue
        case .generation(let id): id.rawValue
        case .opaque(let id): id
        }
    }
}

public enum WorkspaceRunIntegrity: Equatable, Sendable {
    case consistent
    case missingOperationalJob
    case orphanOperationalJob
    case stateMismatch
    case indeterminate
}

public struct WorkspaceRunItem: Identifiable, Equatable, Sendable {
    public var id: WorkspaceRunID
    public var kind: WorkspaceRunKind
    public var state: WorkspaceRunState
    public var subject: WorkspaceRunSubject
    public var operationalJobID: JobID?
    public var operationalState: WorkspaceRunState?
    public var integrity: WorkspaceRunIntegrity
    public var outputAssetIDs: [AssetID]
    public var message: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: WorkspaceRunID,
        kind: WorkspaceRunKind,
        state: WorkspaceRunState,
        subject: WorkspaceRunSubject,
        operationalJobID: JobID? = nil,
        operationalState: WorkspaceRunState? = nil,
        integrity: WorkspaceRunIntegrity = .consistent,
        outputAssetIDs: [AssetID] = [],
        message: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.state = state
        self.subject = subject
        self.operationalJobID = operationalJobID
        self.operationalState = operationalState
        self.integrity = integrity
        self.outputAssetIDs = outputAssetIDs
        self.message = message
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Merges the generation ledger and the lower-level job ledger into one
/// read-only sequence. This is the compatibility bridge for a future generic
/// `Run` store; it avoids duplicating or rewriting historical project data now.
public enum WorkspaceRunProjection {
    /// User-facing activity excludes internal thumbnail work and low-level
    /// generation jobs that do not have a canonical generation ledger entry.
    public static func userVisibleRuns(in workspace: Workspace) -> [WorkspaceRunItem] {
        runs(in: workspace).filter { item in
            switch (item.kind, item.id) {
            case (.imageAnalysis, .job), (.imageGeneration, .generation),
                 (.videoGeneration, .generation): true
            case (.imageAnalysis, .generation), (.imageGeneration, .job),
                 (.videoGeneration, .job), (.thumbnail, _): false
            }
        }
    }

    public static func runs(in workspace: Workspace) -> [WorkspaceRunItem] {
        let generationJobs = Dictionary(
            grouping: workspace.jobs.filter { $0.kind == .generation },
            by: { GenerationID($0.subjectID) }
        ).mapValues { jobs in
            jobs.sorted(by: jobComesFirst)
        }
        let generationIDs = Set(workspace.generations.map(\.id))
        var consumedJobIDs: Set<JobID> = []

        var items = workspace.generations.map { generation in
            let job = generationJobs[generation.id]?.first
            if let job { consumedJobIDs.insert(job.id) }
            let operationalState = job.map { WorkspaceRunState($0.state) }
            return WorkspaceRunItem(
                id: .generation(generation.id),
                kind: generation.mediaKind == .video ? .videoGeneration : .imageGeneration,
                state: WorkspaceRunState(generation.state),
                subject: .generation(generation.id),
                operationalJobID: job?.id,
                operationalState: operationalState,
                integrity: integrity(
                    generationState: generation.state,
                    operationalState: job?.state
                ),
                outputAssetIDs: generation.outputAssetIDs,
                message: job?.message,
                createdAt: generation.createdAt,
                updatedAt: job?.updatedAt ?? generation.createdAt
            )
        }

        items.append(contentsOf: workspace.jobs.compactMap { job in
            if consumedJobIDs.contains(job.id) {
                return nil
            }
            let isOrphanGenerationJob = job.kind == .generation
                && generationIDs.contains(GenerationID(job.subjectID)) == false
            let isDuplicateGenerationJob = job.kind == .generation
                && generationIDs.contains(GenerationID(job.subjectID))
            return WorkspaceRunItem(
                id: .job(job.id),
                kind: WorkspaceRunKind(job.kind),
                state: WorkspaceRunState(job.state),
                subject: subject(for: job),
                operationalJobID: job.id,
                operationalState: WorkspaceRunState(job.state),
                integrity: isOrphanGenerationJob || isDuplicateGenerationJob
                    ? .orphanOperationalJob
                    : .consistent,
                message: job.message,
                createdAt: job.createdAt,
                updatedAt: job.updatedAt
            )
        })

        return items.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.stableSortKey < $1.id.stableSortKey
        }
    }

    private static func subject(for job: JobRecord) -> WorkspaceRunSubject {
        switch job.kind {
        case .analysis, .thumbnail: .asset(AssetID(job.subjectID))
        case .generation: .generation(GenerationID(job.subjectID))
        }
    }

    private static func integrity(
        generationState: GenerationState,
        operationalState: JobState?
    ) -> WorkspaceRunIntegrity {
        guard let operationalState else { return .missingOperationalJob }
        if generationState == .partial { return .indeterminate }
        return WorkspaceRunState(generationState) == WorkspaceRunState(operationalState)
            ? .consistent
            : .stateMismatch
    }

    private static func jobComesFirst(_ lhs: JobRecord, _ rhs: JobRecord) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
    }
}

private extension WorkspaceRunKind {
    init(_ kind: JobKind) {
        switch kind {
        case .analysis: self = .imageAnalysis
        case .generation: self = .imageGeneration
        case .thumbnail: self = .thumbnail
        }
    }
}

private extension WorkspaceRunState {
    init(_ state: GenerationState) {
        switch state {
        case .queued: self = .queued
        case .generating: self = .running
        case .partial: self = .partial
        case .succeeded: self = .succeeded
        case .failed: self = .failed
        case .cancelled: self = .cancelled
        }
    }

    init(_ state: JobState) {
        switch state {
        case .queued: self = .queued
        case .running: self = .running
        case .succeeded: self = .succeeded
        case .failed: self = .failed
        case .cancelled: self = .cancelled
        }
    }
}
