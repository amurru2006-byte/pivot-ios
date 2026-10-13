import Foundation

/// Only a plain numeric prescription is interpreted. Tempo, AMRAP, per-side
/// instructions and pyramids remain the PT's text, not guessed thresholds.
struct TrainingRepRange: Equatable {
    let lower: Int
    let upper: Int
    init?(_ text: String) {
        guard text.count <= 80 else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pattern = "^([0-9]{1,4})(?:[ \\t]*[-–—][ \\t]*([0-9]{1,4}))?(?:[ \\t]+(?:reps?|ripetizioni))?$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let first = Range(match.range(at: 1), in: value), let minimum = Int(value[first]) else { return nil }
        let maximum = Range(match.range(at: 2), in: value).flatMap { Int(value[$0]) } ?? minimum
        guard (1...1000).contains(minimum), (minimum...1000).contains(maximum) else { return nil }
        lower = minimum; upper = maximum
    }
}

struct TrainingRepObservation: Identifiable {
    enum Status: Equatable {
        case uninterpreted, skipped, inProgress, incomplete, belowTarget, inRange, atUpper
        var title: String {
            switch self {
            case .uninterpreted: return "Obiettivo da leggere con il PT"
            case .skipped: return "Esercizio non svolto"
            case .inProgress: return "Allenamento in corso · dato parziale"
            case .incomplete: return "Serie prescritte incomplete"
            case .belowTarget: return "Minimo non raggiunto in tutte le serie"
            case .inRange: return "Minimo del range raggiunto in tutte le serie"
            case .atUpper: return "Limite superiore raggiunto in tutte le serie"
            }
        }
    }
    struct SetContext: Equatable {
        let kg: Double?
        let kind: TrainingSetKind
        let failure: Bool
        let group: String?
        let rest: Int
    }
    let id: UUID
    let date: Date
    let phase: TrainingPhase?
    let target: String
    let range: TrainingRepRange?
    let prescribedCount: Int
    let completedCount: Int
    let upperCount: Int
    let totalReps: Int
    let status: Status
    let context: [SetContext]
    let coachNotes: String
    var comparable: Bool { [.belowTarget, .inRange, .atUpper].contains(status) }
}

struct TrainingRepProgression {
    struct Comparison {
        let previousID: UUID
        let previousDate: Date
        let repDelta: Int
    }
    let observations: [TrainingRepObservation] // Selected session first, otherwise latest; recorded targets.
    let comparison: Comparison?
    let activeConcernCount: Int
    var latest: TrainingRepObservation? { observations.first }

    static func calculate(exercise: TrainingExercise, library: TrainingLibrary, current: TrainingSession? = nil) -> TrainingRepProgression {
        var sessions = library.sessions
        if let current { sessions.removeAll { $0.id == current.id }; sessions.append(current) }
        var observations = sessions.sorted {
            $0.start == $1.start ? $0.id.uuidString < $1.id.uuidString : $0.start > $1.start
        }.compactMap { session -> TrainingRepObservation? in
            guard session.start.timeIntervalSinceReferenceDate.isFinite,
                  session.end.map({ $0.timeIntervalSinceReferenceDate.isFinite && $0 >= session.start }) ?? true,
                  let log = session.exercises.first(where: { sameIdentity($0.exercise, exercise) }) else { return nil }
            return observation(log, session: session)
        }
        if let current, let index = observations.firstIndex(where: { $0.id == current.id }) {
            let selected = observations.remove(at: index)
            observations.insert(selected, at: 0)
        }
        var comparison: Comparison?
        if let latest = observations.first, latest.comparable,
           let previous = observations.dropFirst().first(where: {
               $0.comparable && $0.date < latest.date && $0.phase == latest.phase
                   && $0.range == latest.range && $0.prescribedCount == latest.prescribedCount
                   && $0.context == latest.context && $0.coachNotes == latest.coachNotes
           }) {
            comparison = .init(previousID: previous.id, previousDate: previous.date, repDelta: latest.totalReps - previous.totalReps)
        }
        return .init(observations: observations, comparison: comparison,
                     activeConcernCount: TrainingConcerns.active(for: exercise, in: library).count)
    }

    static func sameIdentity(_ lhs: TrainingExercise, _ rhs: TrainingExercise) -> Bool {
        lhs.id == rhs.id && lhs.catalogID == rhs.catalogID
            && EventCoalescer.normalized(lhs.name) == EventCoalescer.normalized(rhs.name)
            && lhs.usesDuration == rhs.usesDuration && lhs.separateSides == rhs.separateSides
    }
    private static func observation(_ log: TrainingExerciseLog, session: TrainingSession) -> TrainingRepObservation {
        let exercise = log.exercise
        let range = !exercise.isValid || exercise.usesDuration || exercise.separateSides == true ? nil : TrainingRepRange(exercise.reps)
        let required = TrainingSetTemplate.markingOrigins(log.sets, prescribedWorkingSets: exercise.sets)
            .filter { $0.isAdditional == false && $0.resolvedKind != .warmup }
        let completed = required.filter {
            $0.done && $0.canComplete(exercise) && $0.holdTotal == 0
                && ($0.reps.map { (1...1000).contains($0) } ?? false)
                && ($0.kg.map { $0.isFinite && (0...2000).contains($0) } ?? false)
        }
        let structureSupported = required.allSatisfy { [.working, .superset].contains($0.resolvedKind) && $0.holdTotal == 0 }
        let status: TrainingRepObservation.Status
        if log.skipped == true { status = .skipped }
        else if range == nil || !structureSupported { status = .uninterpreted }
        else if session.end == nil { status = .inProgress }
        else if required.count != exercise.sets || completed.count != required.count { status = .incomplete }
        else if let range, completed.allSatisfy({ ($0.reps ?? 0) >= range.upper }) { status = .atUpper }
        else if let range, completed.allSatisfy({ ($0.reps ?? 0) >= range.lower }) { status = .inRange }
        else { status = .belowTarget }
        let context = required.map {
            TrainingRepObservation.SetContext(kg: $0.kg, kind: $0.resolvedKind, failure: $0.reachesFailure,
                                               group: $0.supersetGroup, rest: $0.restSeconds ?? exercise.restSeconds)
        }
        return .init(id: session.id, date: session.start, phase: session.phase, target: exercise.reps, range: range,
                     prescribedCount: exercise.sets, completedCount: completed.count,
                     upperCount: range.map { target in completed.filter { ($0.reps ?? 0) >= target.upper }.count } ?? 0,
                     totalReps: completed.reduce(0) { $0 + ($1.reps ?? 0) }, status: status, context: context,
                     coachNotes: exercise.coachNotes.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
