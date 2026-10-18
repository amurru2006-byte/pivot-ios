import Foundation

struct TrainingDurationWorkload: Codable, Equatable {
    struct SetShape: Codable, Equatable {
        var kind: TrainingSetKind
        var additional: Bool
        var failure: Bool
        var group: String?
        var rest: Int
    }
    var exerciseID: String
    var prescribedSets: Int
    var reps: String
    var isometric: Bool
    var separateSides: Bool
    var sets: [SetShape]

    static func make(_ session: TrainingSession) -> [Self] {
        session.exercises.map { log in
            .init(exerciseID: log.exercise.id, prescribedSets: log.exercise.sets, reps: log.exercise.reps,
                  isometric: log.exercise.usesDuration, separateSides: log.exercise.separateSides == true,
                  sets: TrainingSetTemplate.markingOrigins(log.sets, prescribedWorkingSets: log.exercise.sets).map {
                      .init(kind: $0.resolvedKind, additional: $0.isAdditional == true,
                            failure: $0.reachesFailure, group: $0.supersetGroup, rest: $0.restSeconds ?? log.exercise.restSeconds)
                  })
        }
    }
    var isValid: Bool {
        !exerciseID.isEmpty && exerciseID.count <= 500 && (1...30).contains(prescribedSets)
            && reps.count <= 500 && (1...60).contains(sets.count)
            && sets.allSatisfy { (0...3600).contains($0.rest) && ($0.group?.count ?? 0) <= 20 }
    }
}

/// Captured at the actual start, never backfilled into finished legacy sessions.
/// Retains no weights, symptoms, addresses or model prompt.
struct TrainingDurationPrediction: Codable, Equatable {
    var capturedAt: Date
    var originalStart: Date
    var expectedMinutes: Int
    var lowerMinutes: Int?
    var upperMinutes: Int?
    var sampleIDs: [UUID]
    var timeBand: TrainingDurationTimeBand?
    var phase: TrainingPhase?
    var workload: [TrainingDurationWorkload]

    static func capture(_ estimate: TrainingDurationEstimate, session: TrainingSession, now: Date) -> Self? {
        let stats = estimate.statistics
        let value = Self(capturedAt: now, originalStart: session.start, expectedMinutes: estimate.activityMinutes,
                         lowerMinutes: stats?.lowerMinutes, upperMinutes: stats?.upperMinutes,
                         sampleIDs: estimate.sampleIDs, timeBand: estimate.timeBand, phase: session.phase,
                         workload: TrainingDurationWorkload.make(session))
        return value.isValid && session.end == nil && abs(now.timeIntervalSince(session.start)) <= 60
            && !estimate.sampleIDs.contains(session.id) ? value : nil
    }
    var isValid: Bool {
        capturedAt.timeIntervalSinceReferenceDate.isFinite && originalStart.timeIntervalSinceReferenceDate.isFinite
            && abs(capturedAt.timeIntervalSince(originalStart)) <= 60
            && (1...1440).contains(expectedMinutes) && sampleIDs.count <= 8
            && Set(sampleIDs).count == sampleIDs.count
            && (1...60).contains(workload.count) && Set(workload.map(\.exerciseID)).count == workload.count
            && workload.allSatisfy(\.isValid)
            && ((lowerMinutes == nil && upperMinutes == nil)
                || (lowerMinutes.map { lower in upperMinutes.map { upper in
                    (1...expectedMinutes).contains(lower) && (expectedMinutes...1440).contains(upper) && sampleIDs.count >= 3
                } ?? false } ?? false))
    }
    func actualMinutes(for session: TrainingSession) -> Double? {
        guard isValid, !sampleIDs.contains(session.id), session.durationExcluded != true,
              session.start == originalStart, session.phase == phase,
              workload == TrainingDurationWorkload.make(session),
              let end = session.end, end.timeIntervalSinceReferenceDate.isFinite, end > session.start,
              end.timeIntervalSince(session.start) <= 86400,
              session.exercises.allSatisfy({ log in
                  let required = TrainingSetTemplate.markingOrigins(log.sets, prescribedWorkingSets: log.exercise.sets)
                      .filter { $0.isAdditional != true && $0.resolvedKind != .warmup }
                  return log.skipped != true && required.count == log.exercise.sets
                      && log.sets.allSatisfy { $0.done && $0.canComplete(log.exercise) }
              }) else { return nil }
        return end.timeIntervalSince(session.start) / 60
    }
}

struct TrainingPredictionQuality: Equatable {
    var evaluatedCount: Int
    var meanAbsoluteErrorMinutes: Double?
    var bandCount: Int
    var withinObservedBandCount: Int
    static func make(_ sessions: [TrainingSession]) -> Self {
        var seen = Set<UUID>(), error = 0.0, count = 0, bands = 0, inside = 0
        for session in sessions where seen.insert(session.id).inserted {
            guard let prediction = session.durationPrediction, let actual = prediction.actualMinutes(for: session) else { continue }
            error += abs(actual - Double(prediction.expectedMinutes)); count += 1
            if let lower = prediction.lowerMinutes, let upper = prediction.upperMinutes {
                bands += 1
                if actual >= Double(lower) && actual <= Double(upper) { inside += 1 }
            }
        }
        return .init(evaluatedCount: count, meanAbsoluteErrorMinutes: count == 0 ? nil : error / Double(count),
                     bandCount: bands, withinObservedBandCount: inside)
    }
}
