import Foundation

struct ExercisePerformance: Identifiable {
    var id: UUID
    var date: Date
    var sets: [TrainingSet]
    var volume: Double
    var bestLoad: Double
    var estimatedMax: Double?
    var finished: Bool
    var bestHold: Int = 0
    var totalHold: Int = 0
}

struct ExerciseProgress {
    var performances: [ExercisePerformance]
    var bestLoad: Double? { performances.map(\.bestLoad).max() }
    var bestVolume: Double? { performances.map(\.volume).max() }
    var estimatedMax: Double? { performances.compactMap(\.estimatedMax).max() }
    var bestHold: Int? { performances.map(\.bestHold).filter { $0 > 0 }.max() }
    static func estimatedMax(_ set: TrainingSet) -> Double? {
        guard set.holdTotal == 0, set.done, let kg = set.kg, kg.isFinite, kg > 0, let reps = set.reps, (1...10).contains(reps) else { return nil }
        return reps == 1 ? kg : kg * (1 + Double(reps) / 30)
    }
    static func calculate(exerciseID: String, library: TrainingLibrary, current: TrainingSession? = nil) -> ExerciseProgress {
        var sessions = library.sessions.filter { $0.end != nil }
        if let current { sessions.removeAll { $0.id == current.id }; sessions.append(current) }
        var performances: [ExercisePerformance] = []
        for session in sessions {
            guard let log = session.exercises.first(where: { $0.id == exerciseID }) else { continue }
            let sets = log.sets.filter { $0.done && $0.canComplete(log.exercise) }
            guard !sets.isEmpty else { continue }
            let usesDuration = log.exercise.usesDuration
            let volume: Double = usesDuration ? 0 : sets.reduce(0.0) { $0 + ($1.kg ?? 0) * Double($1.reps ?? 0) }
            let load: Double = sets.compactMap(\.kg).max() ?? 0
            let maximum: Double? = usesDuration ? nil : sets.compactMap { estimatedMax($0) }.max()
            let bestHold: Int = sets.map { max($0.durationSeconds ?? 0, max($0.leftSeconds ?? 0, $0.rightSeconds ?? 0)) }.max() ?? 0
            let totalHold: Int = sets.reduce(0) { $0 + $1.holdTotal }
            let performance = ExercisePerformance(id: session.id, date: session.start, sets: sets, volume: volume, bestLoad: load,
                estimatedMax: maximum, finished: session.end != nil, bestHold: bestHold, totalHold: totalHold)
            performances.append(performance)
        }
        return .init(performances: performances.sorted { $0.date < $1.date })
    }
}

enum TrainingEdits {
    static func withSavedCatalog(_ exercise: TrainingExercise, library: TrainingLibrary) -> TrainingExercise {
        var resolved = exercise
        let planCatalog = library.plans.lazy.flatMap { $0.payload.days }.flatMap { $0.exercises }
            .first { $0.id == exercise.id && $0.catalogID != nil }?.catalogID
        let sessionCatalog = library.sessions.lazy.flatMap { $0.exercises }
            .first { $0.id == exercise.id && $0.exercise.catalogID != nil }?.exercise.catalogID
        resolved.catalogID = planCatalog ?? sessionCatalog ?? exercise.catalogID
        return resolved
    }
    static func preservingCatalogChoices(in session: TrainingSession, library: TrainingLibrary) -> TrainingSession {
        var updated = session
        for index in updated.exercises.indices {
            updated.exercises[index].exercise = withSavedCatalog(updated.exercises[index].exercise, library: library)
        }
        return updated
    }
    static func associateCatalog(exerciseID: String, catalogID: String, library: inout TrainingLibrary) throws {
        guard !exerciseID.isEmpty, !catalogID.isEmpty else { throw TrainingError.invalidPlan }
        var updated = library
        var found = false
        for planIndex in updated.plans.indices {
            for dayIndex in updated.plans[planIndex].payload.days.indices {
                for exerciseIndex in updated.plans[planIndex].payload.days[dayIndex].exercises.indices where updated.plans[planIndex].payload.days[dayIndex].exercises[exerciseIndex].id == exerciseID {
                    updated.plans[planIndex].payload.days[dayIndex].exercises[exerciseIndex].catalogID = catalogID; found = true
                }
            }
        }
        for sessionIndex in updated.sessions.indices {
            for exerciseIndex in updated.sessions[sessionIndex].exercises.indices where updated.sessions[sessionIndex].exercises[exerciseIndex].id == exerciseID {
                updated.sessions[sessionIndex].exercises[exerciseIndex].exercise.catalogID = catalogID; found = true
            }
        }
        guard found else { throw TrainingError.invalidPlan }
        try updated.validate(); library = updated
    }
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
        return TrainingExerciseLog(exercise: exercise, sets: TrainingSetTemplate.next(previous: previous, prescribedWorkingSets: exercise.sets))
    }
}

enum TrainingTiming {
    static func merging(_ session: TrainingSession, previous: TrainingSession?, into record: EventRecord, now: Date = Date()) -> EventRecord {
        // Opening/closing the workout diary or editing sets/notes is not a timer edit.
        // A manually corrected activity must not be replaced by an older session clock.
        guard previous == nil || previous?.start != session.start || previous?.end != session.end else { return record }
        var updated = record
        updated.actualStart = session.start; updated.actualEnd = session.end
        updated.timingFromCalendar = false
        updated.activeMinutes = max(0, Int((session.end ?? now).timeIntervalSince(session.start) / 60))
        updated.status = session.end == nil ? .running : .completed
        updated.updatedAt = now
        return updated
    }
}
