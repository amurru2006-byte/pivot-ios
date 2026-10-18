#if DEBUG && targetEnvironment(simulator)
import Foundation

@MainActor enum TrainingForecastFixture {
    static func install() async throws {
        let exercise = TrainingExercise(id: "forecast-movement", name: "Movimento QA", sets: 1, reps: "6", restSeconds: 60, coachNotes: "")
        let day = TrainingDay(id: "forecast-day", name: "Seduta QA", exercises: [exercise])
        let plan = TrainingPlan(payload: .init(formatVersion: 1, name: "Previsioni QA", days: [day]))
        let now = Date()
        let samples = [60, 75, 90].enumerated().map { index, minutes -> TrainingSession in
            var session = TrainingLibrary().makeSession(plan: plan, day: day, eventID: nil, now: now.addingTimeInterval(-Double(index + 1) * 86400))
            session.end = session.start.addingTimeInterval(Double(minutes) * 60)
            session.exercises[0].sets[0].kg = 40; session.exercises[0].sets[0].reps = 6; session.exercises[0].sets[0].done = true
            return session
        }
        guard WorkoutRuntime.store.change({ $0.training = .init(plans: [plan], activePlanID: plan.id, sessions: samples) }),
              await WorkoutRuntime.store.flushWorkoutChanges() else { throw TrainingError.invalidPlan }
    }
    static func verify() async throws -> String {
        let library = WorkoutRuntime.store.data.training ?? .init()
        try library.validate()
        guard library.sessions.count == 4,
              library.sessions.filter({ $0.end != nil }).allSatisfy({ $0.durationPrediction == nil }),
              let active = library.sessions.first(where: { $0.end == nil }), let prediction = active.durationPrediction,
              prediction.isValid, prediction.expectedMinutes == 75, prediction.sampleIDs.count == 3,
              prediction.originalStart == active.start, prediction.actualMinutes(for: active) == nil,
              active.exercises.allSatisfy({ $0.sets.allSatisfy { !$0.done } }),
              await WorkoutRuntime.store.flushWorkoutChanges() else { throw TrainingError.invalidPlan }
        return "Previsione verificata · nessuno storico inventato"
    }
}
#endif
