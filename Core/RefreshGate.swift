import Foundation

// One operation at a time. A burst becomes one refresh; a change arriving while
// a refresh runs becomes one follow-up, rather than being dropped or run concurrently.
@MainActor
final class RefreshGate {
    private var pending: (@MainActor () async -> Void)?
    private var runner: Task<Void, Never>?
    private let delayNanoseconds: UInt64
    init(delayNanoseconds: UInt64 = 350_000_000) { self.delayNanoseconds = delayNanoseconds }
    func request(_ operation: @escaping @MainActor () async -> Void) {
        pending = operation
        guard runner == nil else { return }
        runner = Task { [weak self] in
            guard let self else { return }
            while self.pending != nil {
                try? await Task.sleep(nanoseconds: self.delayNanoseconds)
                guard let operation = self.pending else { break }
                self.pending = nil
                await operation()
            }
            self.runner = nil
        }
    }
    func waitUntilIdle() async { await runner?.value }
}
