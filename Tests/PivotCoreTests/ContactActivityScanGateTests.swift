import XCTest
@testable import PivotCore

final class ContactActivityScanGateTests: XCTestCase {
    @MainActor private func waitForQueue(_ gate: ContactActivityScanGate, count: Int) async {
        for _ in 0..<1000 {
            if gate.waitingCount == count { return }
            await Task.yield()
        }
        XCTFail("Expected queued scan requests")
    }
    @MainActor func testForegroundRequestWaitsForCompleteBackgroundTransaction() async {
        let gate = ContactActivityScanGate()
        let first = await gate.acquire(); XCTAssertTrue(first)
        var entered = false
        let foreground = Task { @MainActor in
            let acquired = await gate.acquire()
            entered = acquired
            return acquired
        }
        await waitForQueue(gate, count: 1)
        XCTAssertFalse(entered); XCTAssertTrue(gate.isBusy)
        gate.release()
        let acquired = await foreground.value
        XCTAssertTrue(acquired); XCTAssertTrue(entered); XCTAssertTrue(gate.isBusy)
        gate.release(); XCTAssertFalse(gate.isBusy)
    }
    @MainActor func testCancelledWaiterCannotOwnOrReleaseAnotherRequestsScan() async {
        let gate = ContactActivityScanGate()
        let first = await gate.acquire(); XCTAssertTrue(first)
        let cancelled = Task { @MainActor in await gate.acquire() }
        await waitForQueue(gate, count: 1)
        cancelled.cancel()
        XCTAssertTrue(gate.isBusy, "Canceling a waiter must not release the active transaction")
        gate.release()
        let acquired = await cancelled.value
        XCTAssertFalse(acquired); XCTAssertFalse(gate.isBusy)
        let next = await gate.acquire(); XCTAssertTrue(next)
        gate.release()
    }
    @MainActor func testConcurrentWaitersNeverOverlapReadValidatePublishTransactions() async {
        let gate = ContactActivityScanGate()
        let held = await gate.acquire(); XCTAssertTrue(held)
        var active = 0, peak = 0, completed = 0
        let tasks = (0..<8).map { _ in Task { @MainActor in
            guard await gate.acquire() else { return }
            defer { gate.release() }
            active += 1; peak = max(peak, active)
            await Task.yield()
            active -= 1; completed += 1
        } }
        await waitForQueue(gate, count: 8)
        gate.release()
        for task in tasks { await task.value }
        XCTAssertEqual(completed, 8); XCTAssertEqual(peak, 1)
        XCTAssertEqual(active, 0); XCTAssertFalse(gate.isBusy); XCTAssertEqual(gate.waitingCount, 0)
    }
    @MainActor func testAlreadyCancelledCallerDoesNotStartARead() async {
        let gate = ContactActivityScanGate()
        let held = await gate.acquire(); XCTAssertTrue(held)
        let request = Task { @MainActor in await gate.acquire() }
        request.cancel()
        gate.release()
        let result = await request.value
        XCTAssertFalse(result); XCTAssertFalse(gate.isBusy)
    }
}
