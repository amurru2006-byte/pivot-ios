import Foundation

/// One ordering rule for the in-app controls and the Lock Screen. During rest,
/// continue after the completed set before returning to earlier unfinished work.
enum TrainingWorkoutContext {
    struct Selection: Equatable {
        var exercise: TrainingExercise
        var set: TrainingSet
        var workingNumber: Int
        var prescription: String {
            let position = set.resolvedKind == .warmup ? "Warm-up \(set.number)" : "Serie \(workingNumber) di \(exercise.sets)"
            return "\(position) · \(exercise.reps)\(exercise.usesDuration ? "" : " reps")"
        }
    }
    static func next(in session: TrainingSession, focusedSetID: UUID? = nil) -> Selection? {
        guard session.end == nil else { return nil }
        let all = selections(in: session)
        let pending = all.filter { !$0.set.isResolved }
        if let focused = pending.first(where: { $0.set.id == focusedSetID }) { return focused }
        if let origin = session.rest?.setID, let index = all.firstIndex(where: { $0.set.id == origin }),
           let following = all.dropFirst(index + 1).first(where: { !$0.set.isResolved }) { return following }
        return pending.first
    }
    static func restOrigin(in session: TrainingSession) -> Selection? {
        guard let rest = session.rest else { return nil }
        return selections(in: session).first { $0.exercise.id == rest.exerciseID && $0.set.id == rest.setID }
    }
    static func last(in session: TrainingSession) -> Selection? { selections(in: session).last }
    private static func selections(in session: TrainingSession) -> [Selection] {
        session.exercises.filter { $0.skipped != true }.flatMap { log in
            var working = 0
            return log.sets.map { set in
                if set.resolvedKind != .warmup { working += 1 }
                return Selection(exercise: log.exercise, set: set, workingNumber: working)
            }
        }
    }
}
