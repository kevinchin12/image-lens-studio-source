import XCTest
@testable import ImageLensMac

final class WorkspaceManifestSaveCoordinatorTests: XCTestCase {
    func testMaintenanceDrainsStartedSaveBeforeCleanupAndDropsStaleRequest() async throws {
        let coordinator = WorkspaceManifestSaveCoordinator()
        let events = SaveEventRecorder()
        let oldSaveStarted = AsyncLatch()
        let releaseOldSave = AsyncLatch()

        let oldSave = Task {
            try await coordinator.save {
                await events.append("old-start")
                await oldSaveStarted.open()
                await releaseOldSave.wait()
                await events.append("old-finish")
            }
        }
        await oldSaveStarted.wait()

        let maintenance = Task {
            await coordinator.beginMaintenance()
        }
        while !(await coordinator.maintenanceIsActive()) {
            await Task.yield()
        }

        // This represents a delayed autosave that reached the session after
        // cleanup invalidated its generation. Its old snapshot must never be
        // replayed after the cleanup manifest write.
        let staleRequestWasWritten = try await coordinator.save {
            await events.append("stale")
        }
        XCTAssertFalse(staleRequestWasWritten)

        await releaseOldSave.open()
        let didBeginMaintenance = await maintenance.value
        XCTAssertTrue(didBeginMaintenance)

        try await coordinator.saveDuringMaintenance {
            await events.append("cleanup")
        }
        let cleanupEvents = await events.values()
        XCTAssertEqual(cleanupEvents, ["old-start", "old-finish", "cleanup"])

        let needsFreshSave = await coordinator.endMaintenance()
        XCTAssertTrue(needsFreshSave)
        try await coordinator.save {
            await events.append("fresh")
        }

        _ = try await oldSave.value
        let finalEvents = await events.values()
        XCTAssertEqual(
            finalEvents,
            ["old-start", "old-finish", "cleanup", "fresh"]
        )
    }
}

private actor SaveEventRecorder {
    private var storage: [String] = []

    func append(_ value: String) {
        storage.append(value)
    }

    func values() -> [String] {
        storage
    }
}

private actor AsyncLatch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let continuations = waiters
        waiters.removeAll()
        continuations.forEach { $0.resume() }
    }

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            if isOpen {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }
}
