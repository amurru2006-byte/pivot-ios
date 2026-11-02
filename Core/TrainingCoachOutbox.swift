import Foundation
import CryptoKit

/// Durable protocol state, independent of login credentials and browser storage.
/// This type is not yet wired into production persistence or an automatic sender.
struct TrainingCoachOutbox: Codable {
    enum OutboxError: Error {
        case invalidSnapshot, invalidJournal, revisionReused, previousUnreconciled
        case staleRevision, missingOperation, invalidTransition, receiptMismatch
    }
    struct Operation: Codable, Hashable {
        let accountID: String
        let assignmentID: String
        let sessionID: UUID
        let revision: Int
    }
    struct Snapshot: Codable, Equatable {
        let operation: Operation
        let remoteDayID: String
        let prescriptionRevisionID: String
        let records: [TrainingCoachExchange.Record]

        init(preview: TrainingCoachExchange.Preview, revision: Int) throws {
            guard let first = preview.records.first else { throw OutboxError.invalidSnapshot }
            operation = Operation(accountID: preview.link.accountID,
                                  assignmentID: preview.link.assignmentID,
                                  sessionID: first.key.sessionID, revision: revision)
            remoteDayID = preview.link.dayID
            prescriptionRevisionID = preview.link.revisionID
            records = preview.records
            try validate()
        }
        var digest: String {
            get throws {
                try validate()
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                return SHA256.hash(data: try encoder.encode(self)).map { String(format: "%02x", $0) }.joined()
            }
        }
        func validate() throws {
            guard TrainingCoachOutbox.validID(operation.accountID),
                  TrainingCoachOutbox.validID(operation.assignmentID),
                  TrainingCoachOutbox.validID(remoteDayID),
                  TrainingCoachOutbox.validID(prescriptionRevisionID),
                  (1...10000).contains(operation.revision), (1...400).contains(records.count),
                  Set(records.map(\.key)).count == records.count else { throw OutboxError.invalidSnapshot }
            var slots = Set<String>()
            for r in records {
                guard r.key.accountID == operation.accountID,
                      r.key.assignmentID == operation.assignmentID,
                      r.key.sessionID == operation.sessionID,
                      r.prescriptionRevisionID == prescriptionRevisionID,
                      TrainingCoachOutbox.validID(r.key.exerciseID),
                      TrainingCoachOutbox.validID(r.remoteExerciseID),
                      r.supersetGroup.map({ !$0.isEmpty && $0.utf8.count <= 64 }) ?? true
                else { throw OutboxError.invalidSnapshot }
                switch r.role {
                case .personalWarmup: throw OutboxError.invalidSnapshot
                case .prescribedWorking, .coachActivation:
                    guard let slot = r.slotID, TrainingCoachOutbox.validID(slot),
                          slots.insert(r.remoteExerciseID + "\u{0}" + slot).inserted,
                          r.role != .prescribedWorking || r.kind != .warmup
                    else { throw OutboxError.invalidSnapshot }
                case .extra:
                    guard r.slotID == nil, r.kind != .warmup else { throw OutboxError.invalidSnapshot }
                }
                let numbers = [r.kg].compactMap { $0 }
                guard numbers.allSatisfy({ $0.isFinite && (0...2000).contains($0) }),
                      r.reps.map({ (1...1000).contains($0) }) ?? true,
                      r.durationSeconds.map({ (1...86400).contains($0) }) ?? true,
                      [r.leftSeconds, r.rightSeconds].allSatisfy({ $0.map { (0...86400).contains($0) } ?? true })
                else { throw OutboxError.invalidSnapshot }
                if r.status != .completed {
                    guard r.kg == nil, r.reps == nil, r.durationSeconds == nil,
                          r.leftSeconds == nil, r.rightSeconds == nil, !r.toFailure
                    else { throw OutboxError.invalidSnapshot }
                } else {
                    let sides = r.leftSeconds != nil || r.rightSeconds != nil
                    guard !sides || (r.leftSeconds != nil && r.rightSeconds != nil &&
                          (r.leftSeconds ?? 0) + (r.rightSeconds ?? 0) > 0),
                          r.reps != nil || r.durationSeconds != nil || sides
                    else { throw OutboxError.invalidSnapshot }
                }
            }
        }
    }
    enum State: String, Codable { case queued, writing, uncertain, confirmed, conflict }
    enum Outcome: String, Codable { case verifiedAbsent, verifiedCommitted, conflict }
    struct Receipt: Codable, Equatable {
        let operation: Operation
        let digest: String
        let outcome: Outcome
        let remoteWorkoutID: String?
    }
    struct Entry: Codable {
        let snapshot: Snapshot
        let digest: String
        let targetRemoteWorkoutID: String?
        var state: State
        var receipt: Receipt?
    }
    private(set) var entries: [Entry] = []

    init() {}
    private enum CodingKeys: String, CodingKey { case schema, entries }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schema) == 1 else { throw OutboxError.invalidJournal }
        entries = try values.decode([Entry].self, forKey: .entries)
        try validate()
        // A decoded archive may be an older backup. Even "queued" is not proof
        // that the remote write never happened after that archive was created.
        for i in entries.indices where entries[i].state == .queued || entries[i].state == .writing {
            entries[i].state = .uncertain
        }
    }
    func encode(to encoder: Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(1, forKey: .schema)
        try values.encode(entries, forKey: .entries)
    }
    @discardableResult mutating func enqueue(_ snapshot: Snapshot) throws -> Operation {
        try snapshot.validate()
        let digest = try snapshot.digest
        if let old = entries.first(where: { $0.snapshot.operation == snapshot.operation }) {
            guard old.digest == digest else { throw OutboxError.revisionReused }
            return snapshot.operation
        }
        let previous = entries.filter {
            $0.snapshot.operation.accountID == snapshot.operation.accountID &&
            $0.snapshot.operation.assignmentID == snapshot.operation.assignmentID &&
            $0.snapshot.operation.sessionID == snapshot.operation.sessionID
        }
        guard !previous.contains(where: { $0.state != .confirmed }) else { throw OutboxError.previousUnreconciled }
        guard previous.allSatisfy({ $0.snapshot.operation.revision < snapshot.operation.revision })
        else { throw OutboxError.staleRevision }
        guard entries.count < 1000 else { throw OutboxError.invalidJournal }
        let target = previous.max { $0.snapshot.operation.revision < $1.snapshot.operation.revision }?.receipt?.remoteWorkoutID
        entries.append(Entry(snapshot: snapshot, digest: digest, targetRemoteWorkoutID: target, state: .queued, receipt: nil))
        return snapshot.operation
    }
    mutating func begin(_ operation: Operation) throws {
        let i = try index(operation)
        guard entries[i].state == .queued else { throw OutboxError.invalidTransition }
        entries[i].state = .writing
    }
    mutating func markUncertain(_ operation: Operation) throws {
        let i = try index(operation)
        guard entries[i].state == .writing else { throw OutboxError.invalidTransition }
        entries[i].state = .uncertain
    }
    mutating func reconcile(_ receipt: Receipt) throws {
        let i = try index(receipt.operation)
        guard [.writing, .uncertain].contains(entries[i].state),
              entries[i].digest == receipt.digest else { throw OutboxError.receiptMismatch }
        switch receipt.outcome {
        case .verifiedAbsent:
            guard receipt.remoteWorkoutID == nil, entries[i].targetRemoteWorkoutID == nil
            else { throw OutboxError.receiptMismatch }
            entries[i].state = .queued
        case .conflict:
            guard receipt.remoteWorkoutID == nil else { throw OutboxError.receiptMismatch }
            entries[i].state = .conflict
        case .verifiedCommitted:
            guard let remote = receipt.remoteWorkoutID, Self.validID(remote),
                  entries[i].targetRemoteWorkoutID.map({ $0 == remote }) ?? true
            else { throw OutboxError.receiptMismatch }
            entries[i].state = .confirmed
        }
        entries[i].receipt = receipt
    }
    func validate() throws {
        guard entries.count <= 1000,
              Set(entries.map { $0.snapshot.operation }).count == entries.count,
              entries.reduce(0, { $0 + $1.snapshot.records.count }) <= 100000
        else { throw OutboxError.invalidJournal }
        for e in entries {
            try e.snapshot.validate()
            guard try e.snapshot.digest == e.digest,
                  e.targetRemoteWorkoutID.map(Self.validID) ?? true
            else { throw OutboxError.invalidJournal }
            if let receipt = e.receipt {
                guard receipt.operation == e.snapshot.operation, receipt.digest == e.digest,
                      receipt.remoteWorkoutID.map(Self.validID) ?? true
                else { throw OutboxError.invalidJournal }
            }
            if e.state == .confirmed {
                guard let receipt = e.receipt, receipt.outcome == .verifiedCommitted,
                      let remote = receipt.remoteWorkoutID,
                      e.targetRemoteWorkoutID.map({ $0 == remote }) ?? true
                else { throw OutboxError.invalidJournal }
            }
        }
        let groups = Dictionary(grouping: entries) { e in
            e.snapshot.operation.accountID + "\u{0}" + e.snapshot.operation.assignmentID +
                "\u{0}" + e.snapshot.operation.sessionID.uuidString
        }
        for group in groups.values {
            let ordered = group.sorted { $0.snapshot.operation.revision < $1.snapshot.operation.revision }
            guard ordered.first?.targetRemoteWorkoutID == nil else { throw OutboxError.invalidJournal }
            for i in ordered.indices.dropFirst() {
                let previous = ordered[i - 1]
                guard previous.state == .confirmed,
                      ordered[i].targetRemoteWorkoutID == previous.receipt?.remoteWorkoutID
                else { throw OutboxError.invalidJournal }
            }
        }
    }
    private func index(_ operation: Operation) throws -> Int {
        guard let i = entries.firstIndex(where: { $0.snapshot.operation == operation }) else { throw OutboxError.missingOperation }
        return i
    }
    private static func validID(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        value.utf8.count <= 256 && !value.contains("\u{0}")
    }
}
