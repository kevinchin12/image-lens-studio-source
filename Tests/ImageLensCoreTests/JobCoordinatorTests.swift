import Foundation
import XCTest
@testable import ImageLensCore

final class JobCoordinatorTests: XCTestCase {
    func testDefaultLaneLimitsAreIndependent() async {
        let coordinator = JobCoordinator()
        let subjectIDs = (0..<5).map { _ in UUID() }
        let requests = [
            request(.analysis, subjectID: subjectIDs[0]),
            request(.generation, subjectID: subjectIDs[1]),
            request(.analysis, subjectID: subjectIDs[2]),
            request(.generation, subjectID: subjectIDs[3]),
            request(.analysis, subjectID: subjectIDs[4])
        ]
        for request in requests {
            _ = await coordinator.enqueue(request)
        }

        let first = await coordinator.takeReadyJobs(at: time(10))

        XCTAssertEqual(first.map(\.id), [requests[0].id, requests[1].id, requests[2].id])
        XCTAssertEqual(first.filter { $0.request.lane == .analysis }.count, 2)
        XCTAssertEqual(first.filter { $0.request.lane == .generation }.count, 1)

        let completion = await coordinator.finish(
            requests[0].id,
            subjectRevision: requests[0].subjectRevision,
            token: requests[0].freshnessToken,
            outcome: .success,
            at: time(11)
        )
        XCTAssertEqual(completion, .accepted)
        let second = await coordinator.takeReadyJobs(at: time(12))
        XCTAssertEqual(second.map(\.id), [requests[4].id])
    }

    func testAnalysisConcurrencyCannotExceedTwo() async {
        let coordinator = JobCoordinator(configuration: .init(analysisConcurrency: 20))
        let requests = (0..<3).map { _ in request(.analysis) }
        for request in requests {
            _ = await coordinator.enqueue(request)
        }

        let ready = await coordinator.takeReadyJobs()

        XCTAssertEqual(ready.count, 2)
    }

    func testCancellationIsExplicitAndLateResultIsDiscarded() async {
        let coordinator = JobCoordinator(configuration: .init(analysisConcurrency: 1))
        let running = request(.analysis)
        let queued = request(.analysis)
        _ = await coordinator.enqueue(running)
        _ = await coordinator.enqueue(queued)
        _ = await coordinator.takeReadyJobs(at: time(1))

        let cancellation = await coordinator.cancel(running.id, at: time(2))
        XCTAssertEqual(cancellation, .cancellationRequested)
        let lateResult = await coordinator.finish(
            running.id,
            subjectRevision: running.subjectRevision,
            token: running.freshnessToken,
            outcome: .success,
            at: time(3)
        )
        XCTAssertEqual(lateResult, .discardedCancelled)
        let replacement = await coordinator.takeReadyJobs(at: time(4))
        XCTAssertEqual(replacement.map(\.id), [queued.id])

        let queuedCancellation = await coordinator.cancel(queued.id, at: time(5))
        XCTAssertEqual(queuedCancellation, .cancellationRequested)
        let snapshot = await coordinator.job(queued.id)
        XCTAssertEqual(snapshot?.state, .cancelled)
        XCTAssertEqual(snapshot?.cancellationRequested, true)
    }

    func testQueuedCancellationNeverStarts() async {
        let coordinator = JobCoordinator(configuration: .init(generationConcurrency: 1))
        let first = request(.generation)
        let second = request(.generation)
        _ = await coordinator.enqueue(first)
        _ = await coordinator.enqueue(second)
        _ = await coordinator.takeReadyJobs()

        let cancellation = await coordinator.cancel(second.id)
        let snapshot = await coordinator.job(second.id)
        XCTAssertEqual(cancellation, .cancelledBeforeStart)
        XCTAssertEqual(snapshot?.state, .cancelled)
    }

    func testNewRevisionMakesRunningResultStaleAndReplacesQueuedWork() async {
        let coordinator = JobCoordinator(configuration: .init(analysisConcurrency: 1))
        let subjectID = UUID()
        let old = request(
            .analysis,
            subjectID: subjectID,
            revision: 1,
            token: JobFreshnessToken()
        )
        _ = await coordinator.enqueue(old)
        _ = await coordinator.takeReadyJobs(at: time(1))

        let current = request(
            .analysis,
            subjectID: subjectID,
            revision: 2,
            token: JobFreshnessToken()
        )
        _ = await coordinator.enqueue(current)

        let superseded = await coordinator.job(old.id)
        XCTAssertEqual(superseded?.isSuperseded, true)
        let oldResult = await coordinator.finish(
            old.id,
            subjectRevision: old.subjectRevision,
            token: old.freshnessToken,
            outcome: .success,
            at: time(2)
        )
        XCTAssertEqual(oldResult, .discardedStale)
        let oldSnapshot = await coordinator.job(old.id)
        let next = await coordinator.takeReadyJobs(at: time(3))
        XCTAssertEqual(oldSnapshot?.state, .discardedStale)
        XCTAssertEqual(next.map(\.id), [current.id])
    }

    func testWrongCompletionTokenIsDiscarded() async {
        let coordinator = JobCoordinator()
        let job = request(.analysis)
        _ = await coordinator.enqueue(job)
        _ = await coordinator.takeReadyJobs()

        let disposition = await coordinator.finish(
            job.id,
            subjectRevision: job.subjectRevision,
            token: JobFreshnessToken(),
            outcome: .success
        )

        XCTAssertEqual(disposition, .discardedStale)
        let snapshot = await coordinator.job(job.id)
        XCTAssertEqual(snapshot?.state, .discardedStale)
    }

    func testGenerationFailureDoesNotAutomaticallyRetry() async {
        let coordinator = JobCoordinator()
        let generation = request(.generation)
        _ = await coordinator.enqueue(generation)
        _ = await coordinator.takeReadyJobs()

        let result = await coordinator.finish(
            generation.id,
            subjectRevision: generation.subjectRevision,
            token: generation.freshnessToken,
            outcome: .failure(message: "provider rejected request")
        )
        XCTAssertEqual(result, .failed)
        let snapshot = await coordinator.job(generation.id)
        let ready = await coordinator.takeReadyJobs()
        let allJobs = await coordinator.allJobs()
        XCTAssertEqual(snapshot?.state, .failed)
        XCTAssertEqual(snapshot?.failureMessage, "provider rejected request")
        XCTAssertTrue(ready.isEmpty)
        XCTAssertEqual(allJobs.count, 1)
    }

    func testOlderRequestIsDiscardedAtEnqueue() async {
        let coordinator = JobCoordinator()
        let subjectID = UUID()
        let current = request(.analysis, subjectID: subjectID, revision: 3)
        _ = await coordinator.enqueue(current)
        let old = request(.analysis, subjectID: subjectID, revision: 2)

        let disposition = await coordinator.enqueue(old)

        guard case .discardedStale(let snapshot) = disposition else {
            return XCTFail("Expected stale enqueue disposition")
        }
        XCTAssertEqual(snapshot.state, .discardedStale)
        let ready = await coordinator.takeReadyJobs()
        XCTAssertEqual(ready.map(\.id), [current.id])
    }

    private func request(
        _ lane: JobLane,
        subjectID: UUID = UUID(),
        revision: Int = 0,
        token: JobFreshnessToken = JobFreshnessToken()
    ) -> JobRequest {
        JobRequest(
            lane: lane,
            subjectID: subjectID,
            subjectRevision: revision,
            freshnessToken: token,
            enqueuedAt: time(Double(revision))
        )
    }

    private func time(_ value: TimeInterval) -> Date {
        Date(timeIntervalSince1970: value)
    }
}
