import Foundation

// A serial disk owner. Encoding, migrations and atomic file I/O never run on
// MainActor; an unsuccessful write keeps both the previous bytes and the retry.
actor FilePersistence {
    private let directory: URL
    private let file: URL
    private var lastBytes: Data?

    init(directory: URL) {
        self.directory = directory
        file = directory.appendingPathComponent("pivot-data.json")
    }

    func load() throws -> AppData {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: file.path) else { return AppData() }
        let bytes = try Data(contentsOf: file)
        let data = try BackupCodec.decode(bytes)
        lastBytes = bytes
        return data
    }

    func save(_ data: AppData, restoring: Bool = false) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bytes = try BackupCodec.encodeCompact(data)
        let previous = try lastBytes ?? (FileManager.default.fileExists(atPath: file.path) ? Data(contentsOf: file) : nil)
        if let previous {
            let name = restoring ? "before-restore-\(UUID().uuidString).json" : "previous.json"
            try previous.write(to: directory.appendingPathComponent(name), options: .atomic)
        }
        #if os(iOS)
        try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try bytes.write(to: file, options: .atomic)
        #endif
        lastBytes = bytes
    }
}

// UI changes are accepted in memory immediately; nearby changes share a write.
// flush waits for durable storage, and retries a failed latest snapshot.
@MainActor
final class CoalescingWriter<Snapshot> {
    private let write: (Snapshot) async throws -> Void
    private let onResult: (Bool, Error?) -> Void
    private let delayNanoseconds: UInt64
    private var task: Task<Bool, Never>?
    private var latest: Snapshot?
    private var revision: UInt64 = 0
    private var persistedRevision: UInt64 = 0
    var isPending: Bool { revision != persistedRevision }

    init(delayNanoseconds: UInt64 = 150_000_000,
         write: @escaping (Snapshot) async throws -> Void,
         onResult: @escaping (Bool, Error?) -> Void = { _, _ in }) {
        self.delayNanoseconds = delayNanoseconds
        self.write = write
        self.onResult = onResult
    }

    func enqueue(_ snapshot: Snapshot) {
        latest = snapshot
        revision &+= 1
        schedule(delayed: true)
    }

    private func schedule(delayed: Bool) {
        let token = revision, previous = task
        task = Task {
            _ = await previous?.value
            guard token == revision else { return true }
            if delayed { try? await Task.sleep(nanoseconds: delayNanoseconds) }
            guard token == revision, let snapshot = latest else { return true }
            do {
                try await write(snapshot)
                persistedRevision = token
                if token == revision { latest = nil }
                onResult(isPending, nil)
                return true
            } catch {
                onResult(isPending, error)
                return false
            }
        }
    }

    func flush() async -> Bool {
        if task == nil || !isPending { return true }
        _ = await task?.value
        while isPending {
            schedule(delayed: false)
            guard await task?.value == true else { return false }
        }
        return true
    }
}
