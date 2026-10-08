import Foundation

/// The app and Live Activity share completion semantics. A skipped set never
/// contributes to work, records or suggested loads, and needs no invented data.
enum TrainingCompletion {
    enum Outcome: Equatable { case performed, skipped, reopened, invalid }
    @discardableResult
    static func toggle(in session: inout TrainingSession, exerciseIndex: Int, setIndex: Int, now: Date = Date()) -> Outcome {
        guard session.exercises.indices.contains(exerciseIndex),
              session.exercises[exerciseIndex].sets.indices.contains(setIndex),
              session.exercises[exerciseIndex].skipped != true else { return .invalid }
        let exercise = session.exercises[exerciseIndex].exercise
        var set = session.exercises[exerciseIndex].sets[setIndex]
        let result: Outcome
        if set.isResolved {
            set.done = false; set.skipped = nil; set.completedAt = nil
            if session.rest?.setID == set.id { session.rest = nil }
            result = .reopened
        } else if set.explicitlySkippedHold(exercise) {
            set.skipped = true; set.done = false; set.completedAt = nil
            result = .skipped
        } else if set.canComplete(exercise) {
            set.done = true; set.skipped = nil; set.completedAt = now
            let seconds = set.restSeconds ?? exercise.restSeconds
            session.rest = seconds > 0 ? .init(exerciseID: exercise.id, setID: set.id, seconds: seconds, now: now) : nil
            result = .performed
        } else { return .invalid }
        session.exercises[exerciseIndex].sets[setIndex] = set
        return result
    }
    static func skipExercise(in session: inout TrainingSession, at index: Int, reason: String = "") {
        guard session.exercises.indices.contains(index) else { return }
        var log = session.exercises[index]
        // Preserve existing performed work. In that case only remaining sets
        // are skipped; the whole exercise is never labelled non svolto.
        if log.sets.contains(where: \.done) {
            for si in log.sets.indices where !log.sets[si].done { log.sets[si].skipped = true }
        } else { log.skipped = true }
        let value = String(reason.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        log.skipReason = value.isEmpty ? nil : value
        session.exercises[index] = log
    }
    static func resumeExercise(in session: inout TrainingSession, at index: Int) {
        guard session.exercises.indices.contains(index) else { return }
        session.exercises[index].skipped = nil; session.exercises[index].skipReason = nil
        for si in session.exercises[index].sets.indices { session.exercises[index].sets[si].skipped = nil }
    }
}
