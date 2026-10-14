import Foundation

/// A scheduling estimate, not a claim about the statistically most likely duration.
/// Inputs and retained samples remain local; weights and symptoms are not needed.
struct TrainingDurationEstimate: Equatable {
    enum Source: String { case historyMedian, calendar }
    var source: Source
    var activityMinutes: Int
    var sampleIDs: [UUID]
    var sampleMinutes: [Double]
    var observedMinimumMinutes: Double?
    var observedMaximumMinutes: Double?
    var provisional: Bool { sampleIDs.count < 5 }

    static func make(plan: TrainingPlan, day: TrainingDay, library: TrainingLibrary,
                     calendarMinutes: Int, now: Date) -> Self? {
        guard (1...1440).contains(calendarMinutes),
              now.timeIntervalSinceReferenceDate.isFinite,
              plan.payload.days.contains(where: { $0.id == day.id }),
              !day.exercises.isEmpty, day.exercises.allSatisfy(\.isValid) else { return nil }
        let phase = TrainingPhase.resolved(plan: plan.payload, day: day)
        let from = PivotDate.calendar.date(byAdding: .day, value: -180, to: now)!
        let candidates = TrainingHistory.sessions(planID: plan.id, dayID: day.id, dayName: day.name, library: library)
            .filter { session in
                guard session.start.timeIntervalSinceReferenceDate.isFinite,
                      let end = session.end, end.timeIntervalSinceReferenceDate.isFinite,
                      session.start >= from, end <= now, end > session.start,
                      end.timeIntervalSince(session.start) <= 86400,
                      session.phase == phase, session.exercises.map(\.exercise) == day.exercises else { return false }
                return session.exercises.allSatisfy { log in
                    let required = TrainingSetTemplate.markingOrigins(log.sets, prescribedWorkingSets: log.exercise.sets)
                        .filter { $0.isAdditional == false && $0.resolvedKind != .warmup }
                    return log.skipped != true && required.count == log.exercise.sets
                        && required.allSatisfy { $0.done && $0.canComplete(log.exercise) }
                        && log.sets.allSatisfy { $0.done && $0.canComplete(log.exercise) }
                }
            }
        // A different warm-up/additional-set structure is a different timed workload.
        // Compare to the structure that would actually be reused for the next session.
        let next = library.makeSession(plan: plan, day: day, eventID: nil, now: now)
        let expected = structure(next)
        var seen: Set<UUID> = []
        let samples = Array(candidates.filter { seen.insert($0.id).inserted && structure($0) == expected }.prefix(8))
        let minutes = samples.map { $0.end!.timeIntervalSince($0.start) / 60 }
        let sorted = minutes.sorted()
        let activity: Int
        let source: Source
        if sorted.count >= 3 {
            let middle = sorted.count / 2
            let median = sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
            // Round upwards: the estimate must not lose the last partial minute.
            activity = Int(ceil(median)); source = .historyMedian
        } else {
            activity = calendarMinutes; source = .calendar
        }
        return .init(source: source, activityMinutes: activity, sampleIDs: samples.map(\.id),
                     sampleMinutes: minutes, observedMinimumMinutes: sorted.first, observedMaximumMinutes: sorted.last)
    }

    private struct SetShape: Equatable {
        var kind: TrainingSetKind
        var additional: Bool
        var failure: Bool
        var group: String?
        var rest: Int
    }
    private static func structure(_ session: TrainingSession) -> [[SetShape]] {
        session.exercises.map { log in
            TrainingSetTemplate.markingOrigins(log.sets, prescribedWorkingSets: log.exercise.sets).map {
                .init(kind: $0.resolvedKind, additional: $0.isAdditional == true,
                      failure: $0.reachesFailure, group: $0.supersetGroup,
                      rest: $0.restSeconds ?? log.exercise.restSeconds)
            }
        }
    }
}

struct CalendarTimeBudget: Equatable {
    var activityMinutes: Int
    var travelBeforeMinutes: Int
    var preparationMinutes: Int
    var travelAfterMinutes: Int
    var marginMinutes: Int
    var occupiedMinutes: Int { activityMinutes + travelBeforeMinutes + preparationMinutes + travelAfterMinutes + marginMinutes }
    var beforeMinutes: Int { travelBeforeMinutes + preparationMinutes }
    var afterMinutes: Int { travelAfterMinutes + marginMinutes }

    /// nil means unconfirmed, including a missing preparation time. Explicit zero is valid.
    static func confirmed(activityMinutes: Int, rule: EventRule, preparationMinutes: Int?, marginMinutes: Int = 0) -> Self? {
        guard rule.travelConfirmed, (1...1440).contains(activityMinutes),
              (0...1440).contains(rule.travelBeforeMinutes), (0...1440).contains(rule.travelAfterMinutes),
              let preparationMinutes, (0...1440).contains(preparationMinutes),
              (0...1440).contains(marginMinutes) else { return nil }
        let value = Self(activityMinutes: activityMinutes, travelBeforeMinutes: rule.travelBeforeMinutes,
                         preparationMinutes: preparationMinutes, travelAfterMinutes: rule.travelAfterMinutes,
                         marginMinutes: marginMinutes)
        return value.occupiedMinutes <= 1440 ? value : nil
    }
}
