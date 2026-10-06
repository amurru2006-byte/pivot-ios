import Foundation

struct ExercisePerformance: Identifiable {
    var id: UUID
    var date: Date
    var sets: [TrainingSet]
    var volume: Double
    var bestLoad: Double
    var estimatedMax: Double?
    var finished: Bool
}

struct ExerciseProgress {
    var performances: [ExercisePerformance]
    var bestLoad: Double? { performances.map(\.bestLoad).max() }
    var bestVolume: Double? { performances.map(\.volume).max() }
    var estimatedMax: Double? { performances.compactMap(\.estimatedMax).max() }
    static func estimatedMax(_ set: TrainingSet) -> Double? {
        guard set.done, let kg = set.kg, kg.isFinite, kg > 0, let reps = set.reps, (1...10).contains(reps) else { return nil }
        return reps == 1 ? kg : kg * (1 + Double(reps) / 30)
    }
    static func calculate(exerciseID: String, library: TrainingLibrary, current: TrainingSession? = nil) -> ExerciseProgress {
        var sessions = library.sessions.filter { $0.end != nil }
        if let current { sessions.removeAll { $0.id == current.id }; sessions.append(current) }
        let performances = sessions.compactMap { session -> ExercisePerformance? in
            guard let log = session.exercises.first(where: { $0.id == exerciseID }) else { return nil }
            let sets = log.sets.filter { $0.done && ($0.kg.map { $0.isFinite && $0 >= 0 } ?? false) && ($0.reps.map { $0 > 0 } ?? false) }
            guard !sets.isEmpty else { return nil }
            return .init(id: session.id, date: session.start, sets: sets,
                         volume: sets.reduce(0) { $0 + ($1.kg ?? 0) * Double($1.reps ?? 0) }, bestLoad: sets.compactMap(\.kg).max() ?? 0,
                         estimatedMax: sets.compactMap { estimatedMax($0) }.max(), finished: session.end != nil)
        }.sorted { $0.date < $1.date }
        return .init(performances: performances)
    }
}

enum TrainingEdits {
    static func revise(planID: UUID, payload: TrainingPlanPayload, note: String, library: inout TrainingLibrary, now: Date = Date()) throws {
        try payload.validate()
        guard let index = library.plans.firstIndex(where: { $0.id == planID }) else { throw TrainingError.invalidPlan }
        guard library.plans[index].payload != payload else { return }
        var updated = library
        var revisions = updated.plans[index].revisions ?? []
        revisions.append(.init(payload: updated.plans[index].payload, date: now, note: note))
        updated.plans[index].revisions = revisions; updated.plans[index].payload = payload
        try updated.validate(); library = updated
        // Recorded sessions contain their own prescription snapshots and remain unchanged.
    }
    static func replace(in session: inout TrainingSession, exerciseID: String, with replacement: TrainingExercise, library: TrainingLibrary) throws {
        guard replacement.isValid, let index = session.exercises.firstIndex(where: { $0.id == exerciseID }),
              !session.exercises[index].sets.contains(where: \.done),
              replacement.id == exerciseID || !session.exercises.contains(where: { $0.id == replacement.id }) else { throw TrainingError.invalidPlan }
        var updated = session
        updated.exercises[index] = newLog(replacement, library: library, before: session.start)
        session = updated
    }
    static func add(to session: inout TrainingSession, exercise: TrainingExercise, library: TrainingLibrary) throws {
        guard exercise.isValid, !session.exercises.contains(where: { $0.id == exercise.id }), session.exercises.count < 40 else { throw TrainingError.invalidPlan }
        session.exercises.append(newLog(exercise, library: library, before: session.start))
    }
    private static func newLog(_ exercise: TrainingExercise, library: TrainingLibrary, before date: Date) -> TrainingExerciseLog {
        let previous = library.previous(exerciseID: exercise.id, before: date)
        return TrainingExerciseLog(exercise: exercise, sets: (1...exercise.sets).map { number in
            let old = previous?.sets.first { $0.number == number && $0.done }
            return TrainingSet(number: number, kg: old?.kg, reps: old?.reps)
        })
    }
}
