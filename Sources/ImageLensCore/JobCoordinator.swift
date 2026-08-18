import Foundation

public enum JobLane: String, Codable, CaseIterable, Hashable, Sendable {
    case analysis
    case generation
}

/// Identifies the exact input incarnation a job was created for.
/// A new token can supersede work even when the numeric revision is unchanged.
public struct JobFreshnessToken: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct JobRequest: Codable, Equatable, Identifiable, Sendable {
    public let id: JobID
    public let lane: JobLane
    public let subjectID: UUID
    public let subjectRevision: Int
    public let freshnessToken: JobFreshnessToken
    public let enqueuedAt: Date

    public init(
        id: JobID = JobID(),
        lane: JobLane,
        subjectID: UUID,
        subjectRevision: Int,
        freshnessToken: JobFreshnessToken = JobFreshnessToken(),
        enqueuedAt: Date = .now
    ) {
        self.id = id
        self.lane = lane
        self.subjectID = subjectID
        self.subjectRevision = subjectRevision
        self.freshnessToken = freshnessToken
        self.enqueuedAt = enqueuedAt
    }
}

public enum CoordinatedJobState: String, Codable, Equatable, Sendable {
    case queued
    case running
    case succeeded
    case failed
    case cancelled
    case discardedStale
}

public struct CoordinatedJobSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let request: JobRequest
    public let state: CoordinatedJobState
    public let cancellationRequested: Bool
    public let isSuperseded: Bool
    public let startedAt: Date?
    public let finishedAt: Date?
    public let failureMessage: String?

    public var id: JobID { request.id }
}

/// A lease freezes the revision and token that an executor must return on completion.
public struct JobLease: Codable, Equatable, Identifiable, Sendable {
    public let request: JobRequest
    public let startedAt: Date

    public var id: JobID { request.id }
}

public enum JobEnqueueDisposition: Equatable, Sendable {
    case queued(CoordinatedJobSnapshot)
    case discardedStale(CoordinatedJobSnapshot)
    case duplicateID(CoordinatedJobSnapshot)
}

public enum JobCancellationDisposition: Equatable, Sendable {
    case cancelledBeforeStart
    case cancellationRequested
    case alreadyTerminal(CoordinatedJobState)
    case unknownJob
}

public enum JobExecutionOutcome: Equatable, Sendable {
    case success
    case failure(message: String)
}

public enum JobResultDisposition: Equatable, Sendable {
    case accepted
    case failed
    case discardedStale
    case discardedCancelled
    case notRunning(CoordinatedJobState)
    case unknownJob
}

/// A network-agnostic scheduler and freshness state machine.
///
/// The coordinator never starts `Task`s itself. Callers enqueue work, claim leases with
/// `takeReadyJobs`, execute those leases, and report results. This keeps provider and UI
/// policy outside Core while making concurrency, cancellation, and stale-result behavior
/// deterministic and directly testable.
public actor JobCoordinator {
    public struct Configuration: Equatable, Sendable {
        public var analysisConcurrency: Int
        public var generationConcurrency: Int

        public init(analysisConcurrency: Int = 2, generationConcurrency: Int = 1) {
            self.analysisConcurrency = min(2, max(1, analysisConcurrency))
            self.generationConcurrency = max(1, generationConcurrency)
        }

        fileprivate func limit(for lane: JobLane) -> Int {
            switch lane {
            case .analysis: analysisConcurrency
            case .generation: generationConcurrency
            }
        }
    }

    private struct FreshnessKey: Hashable, Sendable {
        let lane: JobLane
        let subjectID: UUID
    }

    private struct Freshness: Equatable, Sendable {
        let revision: Int
        let token: JobFreshnessToken
    }

    private struct Entry: Sendable {
        let request: JobRequest
        var state: CoordinatedJobState
        var cancellationRequested = false
        var startedAt: Date?
        var finishedAt: Date?
        var failureMessage: String?
    }

    private let configuration: Configuration
    private var entries: [JobID: Entry] = [:]
    private var pendingIDs: [JobID] = []
    private var latestFreshness: [FreshnessKey: Freshness] = [:]

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    @discardableResult
    public func enqueue(_ request: JobRequest) -> JobEnqueueDisposition {
        if let existing = entries[request.id] {
            return .duplicateID(snapshot(for: existing))
        }

        let key = freshnessKey(for: request)
        let freshness = Freshness(
            revision: request.subjectRevision,
            token: request.freshnessToken
        )

        if let latest = latestFreshness[key], request.subjectRevision < latest.revision {
            let entry = Entry(request: request, state: .discardedStale)
            entries[request.id] = entry
            return .discardedStale(snapshot(for: entry))
        }

        if latestFreshness[key] != freshness {
            latestFreshness[key] = freshness
            _ = discardSupersededQueuedJobs(for: key)
        }

        let entry = Entry(request: request, state: .queued)
        entries[request.id] = entry
        pendingIDs.append(request.id)
        return .queued(snapshot(for: entry))
    }

    /// Claims every job that currently fits its lane's concurrency budget.
    /// Returned order follows enqueue order; limits are enforced independently per lane.
    public func takeReadyJobs(at timestamp: Date = .now) -> [JobLease] {
        var runningCounts = Dictionary(
            uniqueKeysWithValues: JobLane.allCases.map { lane in
                (lane, runningCount(in: lane))
            }
        )
        var leases: [JobLease] = []

        for id in pendingIDs {
            guard var entry = entries[id], entry.state == .queued else { continue }
            guard isCurrent(entry.request) else {
                entry.state = .discardedStale
                entry.finishedAt = timestamp
                entries[id] = entry
                continue
            }

            let lane = entry.request.lane
            guard runningCounts[lane, default: 0] < configuration.limit(for: lane) else {
                continue
            }

            entry.state = .running
            entry.startedAt = timestamp
            entries[id] = entry
            runningCounts[lane, default: 0] += 1
            leases.append(JobLease(request: entry.request, startedAt: timestamp))
        }

        pendingIDs.removeAll { entries[$0]?.state != .queued }
        return leases
    }

    /// Cancels queued work immediately. Running work is also made terminal and the
    /// `.cancellationRequested` result tells the caller to cancel its underlying task.
    @discardableResult
    public func cancel(_ id: JobID, at timestamp: Date = .now) -> JobCancellationDisposition {
        guard var entry = entries[id] else { return .unknownJob }

        switch entry.state {
        case .queued:
            entry.state = .cancelled
            entry.cancellationRequested = true
            entry.finishedAt = timestamp
            entries[id] = entry
            pendingIDs.removeAll { $0 == id }
            return .cancelledBeforeStart
        case .running:
            entry.state = .cancelled
            entry.cancellationRequested = true
            entry.finishedAt = timestamp
            entries[id] = entry
            return .cancellationRequested
        case .succeeded, .failed, .cancelled, .discardedStale:
            return .alreadyTerminal(entry.state)
        }
    }

    /// Advances the authoritative revision/token without creating a job.
    /// Queued work is discarded immediately; running work is rejected when it reports back.
    @discardableResult
    public func updateFreshness(
        lane: JobLane,
        subjectID: UUID,
        revision: Int,
        token: JobFreshnessToken
    ) -> [JobID] {
        let key = FreshnessKey(lane: lane, subjectID: subjectID)
        if let latest = latestFreshness[key], revision < latest.revision {
            return []
        }

        let freshness = Freshness(revision: revision, token: token)
        guard latestFreshness[key] != freshness else { return [] }
        latestFreshness[key] = freshness
        return discardSupersededQueuedJobs(for: key)
    }

    /// Accepts a result only when it belongs to a running lease and its frozen
    /// revision/token still match the coordinator's latest input incarnation.
    @discardableResult
    public func finish(
        _ id: JobID,
        subjectRevision: Int,
        token: JobFreshnessToken,
        outcome: JobExecutionOutcome,
        at timestamp: Date = .now
    ) -> JobResultDisposition {
        guard var entry = entries[id] else { return .unknownJob }
        if entry.state == .cancelled { return .discardedCancelled }
        guard entry.state == .running else { return .notRunning(entry.state) }

        let requestMatchesResult = entry.request.subjectRevision == subjectRevision
            && entry.request.freshnessToken == token
        guard requestMatchesResult, isCurrent(entry.request) else {
            entry.state = .discardedStale
            entry.finishedAt = timestamp
            entries[id] = entry
            return .discardedStale
        }

        entry.finishedAt = timestamp
        switch outcome {
        case .success:
            entry.state = .succeeded
            entries[id] = entry
            return .accepted
        case .failure(let message):
            entry.state = .failed
            entry.failureMessage = message
            entries[id] = entry
            return .failed
        }
    }

    public func job(_ id: JobID) -> CoordinatedJobSnapshot? {
        entries[id].map(snapshot(for:))
    }

    public func allJobs() -> [CoordinatedJobSnapshot] {
        entries.values
            .map(snapshot(for:))
            .sorted { lhs, rhs in
                if lhs.request.enqueuedAt != rhs.request.enqueuedAt {
                    return lhs.request.enqueuedAt < rhs.request.enqueuedAt
                }
                return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
            }
    }

    private func runningCount(in lane: JobLane) -> Int {
        entries.values.reduce(into: 0) { count, entry in
            if entry.request.lane == lane && entry.state == .running {
                count += 1
            }
        }
    }

    private func discardSupersededQueuedJobs(for key: FreshnessKey) -> [JobID] {
        var discarded: [JobID] = []
        for id in pendingIDs {
            guard var entry = entries[id],
                  entry.state == .queued,
                  freshnessKey(for: entry.request) == key,
                  !isCurrent(entry.request) else {
                continue
            }
            entry.state = .discardedStale
            entries[id] = entry
            discarded.append(id)
        }
        pendingIDs.removeAll { entries[$0]?.state != .queued }
        return discarded
    }

    private func freshnessKey(for request: JobRequest) -> FreshnessKey {
        FreshnessKey(lane: request.lane, subjectID: request.subjectID)
    }

    private func isCurrent(_ request: JobRequest) -> Bool {
        latestFreshness[freshnessKey(for: request)] == Freshness(
            revision: request.subjectRevision,
            token: request.freshnessToken
        )
    }

    private func snapshot(for entry: Entry) -> CoordinatedJobSnapshot {
        CoordinatedJobSnapshot(
            request: entry.request,
            state: entry.state,
            cancellationRequested: entry.cancellationRequested,
            isSuperseded: entry.state == .discardedStale || !isCurrent(entry.request),
            startedAt: entry.startedAt,
            finishedAt: entry.finishedAt,
            failureMessage: entry.failureMessage
        )
    }
}
