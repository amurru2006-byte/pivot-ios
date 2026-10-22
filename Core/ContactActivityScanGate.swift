import Foundation

/// Serializes the complete read/validate/publish transaction, not only the
/// EventKit query. A foreground request waits for a navigation refresh instead
/// of mistaking "already reading" for an unverified empty calendar.
@MainActor
final class ContactActivityScanGate {
    private(set) var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    var waitingCount: Int { waiters.count }

    func acquire() async -> Bool {
        guard !Task.isCancelled else { return false }
        while isBusy {
            await withCheckedContinuation { waiters.append($0) }
            guard !Task.isCancelled else { return false }
        }
        guard !Task.isCancelled else { return false }
        isBusy = true
        return true
    }

    func release() {
        guard isBusy else { return }
        isBusy = false
        let pending = waiters
        waiters.removeAll(keepingCapacity: true)
        for waiter in pending { waiter.resume() }
    }
}
