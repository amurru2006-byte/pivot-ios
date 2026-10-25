import Foundation

/// Offline preflight only. No transport, share target, persistence or UI is
/// connected until the external service's supported write channel is verified.
enum TrainingCoachExchange {
    enum Role: String, Codable { case prescribedWorking, coachActivation, extra, personalWarmup }
    enum LoadBasis: String, Codable { case unspecified, total, perHand, perSide, assistance, resistance }
    enum Status: String, Codable { case completed, skipped, notPerformed }
    enum ExchangeError: Error { case unfinishedSession, identityMismatch, ambiguousMapping, invalidMeasurements, invalidSnapshot }

    struct SetLink: Equatable {
        let sourceID: UUID
        let slotID: String?
        let role: Role
    }
    struct ExerciseLink: Equatable {
        let sourceID: String
        let remoteID: String
        let loadBasis: LoadBasis
        let sets: [SetLink]
    }
    struct Link: Equatable {
        let accountID: String
        let assignmentID: String
        let revisionID: String
        let dayID: String
        let sourcePlanID: UUID
        let sourceDayID: String
        let exercises: [ExerciseLink]
    }
    /// Corrections and retries keep this identity. A coach's newer revision
    /// does not turn the same performed set into another workout record.
    struct RecordKey: Equatable, Hashable, Codable {
        let accountID: String
        let assignmentID: String
        let sessionID: UUID
        let exerciseID: String
        let setID: UUID
    }
    struct Record: Equatable {
        let key: RecordKey
        let remoteExerciseID: String
        let prescriptionRevisionID: String
        let slotID: String?
        let role: Role
        let kind: TrainingSetKind
        let status: Status
        let loadBasis: LoadBasis
        let kg: Double?
        let reps: Int?
        let durationSeconds: Int?
        let leftSeconds: Int?
        let rightSeconds: Int?
        let toFailure: Bool
        let supersetGroup: String?
    }
    struct Preview: Equatable {
        let link: Link
        let records: [Record]
        let excludedPersonalWarmups: [UUID]
        let exerciseNotes: [String: String]
        let sessionNote: String
        // Deliberately not a writable/synced state. A local preview or Share
        // action must never be presented as confirmation from FitPros.
        var canSend: Bool { false }
    }

    static func preview(session: TrainingSession, link: Link, accountID: String) throws -> Preview {
        guard let end = session.end, end >= session.start,
              session.start.timeIntervalSinceReferenceDate.isFinite,
              end.timeIntervalSinceReferenceDate.isFinite else { throw ExchangeError.unfinishedSession }
        guard validID(accountID), accountID == link.accountID,
              [link.assignmentID, link.revisionID, link.dayID, link.sourceDayID].allSatisfy(validID),
              session.planID == link.sourcePlanID, session.dayID == link.sourceDayID else { throw ExchangeError.identityMismatch }
        guard (1...40).contains(session.exercises.count),
              session.notes.utf8.count <= 20000,
              Set(session.exercises.map(\.id)).count == session.exercises.count,
              Set(link.exercises.map(\.sourceID)) == Set(session.exercises.map(\.id)),
              Set(link.exercises.map(\.sourceID)).count == link.exercises.count,
              Set(link.exercises.map(\.remoteID)).count == link.exercises.count else { throw ExchangeError.ambiguousMapping }
        var records: [Record] = []
        var warmups: [UUID] = []
        for log in session.exercises {
            guard let exercise = link.exercises.first(where: { $0.sourceID == log.id }),
                  validID(exercise.sourceID), validID(exercise.remoteID),
                  log.notes.utf8.count <= 10000,
                  (1...60).contains(log.sets.count),
                  Set(log.sets.map(\.id)).count == log.sets.count,
                  Set(exercise.sets.map(\.sourceID)) == Set(log.sets.map(\.id)),
                  Set(exercise.sets.map(\.sourceID)).count == exercise.sets.count else { throw ExchangeError.ambiguousMapping }
            let slotIDs = exercise.sets.compactMap(\.slotID)
            guard Set(slotIDs).count == slotIDs.count else { throw ExchangeError.ambiguousMapping }
            for set in log.sets {
                guard let binding = exercise.sets.first(where: { $0.sourceID == set.id }),
                      !(set.done && (set.skipped == true || log.skipped == true)) else { throw ExchangeError.ambiguousMapping }
                switch binding.role {
                case .personalWarmup:
                    guard set.resolvedKind == .warmup, binding.slotID == nil else { throw ExchangeError.ambiguousMapping }
                    warmups.append(set.id)
                    continue
                case .prescribedWorking:
                    guard set.resolvedKind != .warmup, set.isAdditional != true,
                          binding.slotID.map(validID) == true else { throw ExchangeError.ambiguousMapping }
                case .coachActivation:
                    // Explicitly assigned activation is not a personal warm-up.
                    guard binding.slotID.map(validID) == true else { throw ExchangeError.ambiguousMapping }
                case .extra:
                    guard set.resolvedKind != .warmup, set.isAdditional != false,
                          binding.slotID == nil else { throw ExchangeError.ambiguousMapping }
                }
                let status: Status = set.done ? .completed : (set.skipped == true || log.skipped == true ? .skipped : .notPerformed)
                if status == .completed {
                    guard set.canComplete(log.exercise),
                          set.kg.map({ $0.isFinite && (0...2000).contains($0) }) ?? true,
                          set.reps.map({ (0...1000).contains($0) }) ?? true,
                          [set.durationSeconds, set.leftSeconds, set.rightSeconds].allSatisfy({ $0.map { (0...86400).contains($0) } ?? true })
                    else { throw ExchangeError.invalidMeasurements }
                }
                let performed = status == .completed
                records.append(Record(key: .init(accountID: accountID, assignmentID: link.assignmentID, sessionID: session.id,
                                                  exerciseID: log.id, setID: set.id),
                                      remoteExerciseID: exercise.remoteID, prescriptionRevisionID: link.revisionID,
                                      slotID: binding.slotID, role: binding.role,
                                      kind: set.resolvedKind, status: status, loadBasis: exercise.loadBasis,
                                      kg: performed ? set.kg : nil, reps: performed ? set.reps : nil,
                                      durationSeconds: performed ? set.durationSeconds : nil,
                                      leftSeconds: performed ? set.leftSeconds : nil, rightSeconds: performed ? set.rightSeconds : nil,
                                      toFailure: performed && set.reachesFailure, supersetGroup: set.supersetGroup))
            }
        }
        let notes = Dictionary(uniqueKeysWithValues: session.exercises.map { ($0.id, $0.notes) })
        return Preview(link: link, records: records, excludedPersonalWarmups: warmups,
                       exerciseNotes: notes, sessionNote: session.notes)
    }

    struct Prescription: Equatable {
        let accountID: String
        let assignmentID: String
        let exerciseID: String
        let slotID: String
        let revisionID: String
        let observedAt: Date
        let loadBasis: LoadBasis
        // A real range remains a range: never replace it by its upper bound.
        let kg: ClosedRange<Double>?
    }
    enum RevisionStatus: Equatable { case notChecked, unchanged, updated }
    enum LoadRelation: Equatable { case notComparable, below, within, above }
    struct Review: Equatable {
        let previous: Prescription
        let current: Prescription?
        let actualKG: Double?
        let revisionStatus: RevisionStatus
        let relationToPrevious: LoadRelation
        // No recommended weight or automatic modification of the coach's plan.
    }
    static func review(record: Record, previous: Prescription, current: Prescription?, sessionEndedAt: Date) throws -> Review {
        guard valid(previous), sessionEndedAt.timeIntervalSinceReferenceDate.isFinite,
              previous.observedAt <= sessionEndedAt, previous.revisionID == record.prescriptionRevisionID,
              record.key.accountID == previous.accountID, record.key.assignmentID == previous.assignmentID,
              record.remoteExerciseID == previous.exerciseID, record.slotID == previous.slotID else { throw ExchangeError.invalidSnapshot }
        if let current {
            guard valid(current), current.accountID == previous.accountID,
                  current.assignmentID == previous.assignmentID, current.exerciseID == previous.exerciseID,
                  current.slotID == previous.slotID, current.observedAt >= previous.observedAt else { throw ExchangeError.invalidSnapshot }
        }
        let revisionStatus: RevisionStatus
        if let current, current.observedAt >= sessionEndedAt {
            revisionStatus = current.revisionID == previous.revisionID && current.kg == previous.kg
                && current.loadBasis == previous.loadBasis ? .unchanged : .updated
        } else { revisionStatus = .notChecked }
        let actual = record.status == .completed ? record.kg : nil
        guard actual.map({ $0.isFinite && (0...2000).contains($0) }) ?? true else { throw ExchangeError.invalidMeasurements }
        let relation: LoadRelation
        if record.role == .prescribedWorking, previous.loadBasis != .unspecified,
           record.loadBasis == previous.loadBasis, let actual, actual.isFinite, let target = previous.kg {
            relation = actual < target.lowerBound ? .below : (actual > target.upperBound ? .above : .within)
        } else { relation = .notComparable }
        return Review(previous: previous, current: current, actualKG: actual,
                      revisionStatus: revisionStatus, relationToPrevious: relation)
    }
    private static func validID(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf8.count <= 256
    }
    private static func valid(_ value: Prescription) -> Bool {
        [value.accountID, value.assignmentID, value.exerciseID, value.slotID, value.revisionID].allSatisfy(validID)
            && value.observedAt.timeIntervalSinceReferenceDate.isFinite
            && (value.kg.map { $0.lowerBound.isFinite && $0.upperBound.isFinite && $0.lowerBound >= 0 && $0.upperBound <= 2000 } ?? true)
    }
}
