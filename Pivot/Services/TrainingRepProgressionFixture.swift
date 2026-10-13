#if DEBUG && targetEnvironment(simulator)
import Foundation
@MainActor
enum TrainingRepProgressionFixture {
    static func install() async throws {
        let exercise = TrainingExercise(id: "progression-exercise", name: "Movimento progressione TEST", sets: 3, reps: "6–8", restSeconds: 60, coachNotes: "Dati sintetici")
        let day = TrainingDay(id: "progression-day", name: "Giornata TEST", exercises: [exercise])
        let plan = TrainingPlan(payload: .init(formatVersion: 1, name: "Progressione TEST", days: [day], phase: .loading))
        let now = Date()
        let sessions = [6, 8].enumerated().map { index, reps -> TrainingSession in
            var saved = TrainingLibrary().makeSession(plan: plan, day: day, eventID: nil, now: now.addingTimeInterval(Double(index - 2) * 86400))
            saved.end = saved.start.addingTimeInterval(600)
            for set in saved.exercises[0].sets.indices {
                saved.exercises[0].sets[set].kg = 40; saved.exercises[0].sets[set].reps = reps; saved.exercises[0].sets[set].done = true
            }
            return saved
        }
        let concern = TrainingConcern(area: "Zona progressione TEST", observedAt: now, exercises: [.init(exercise)], createdAt: now, updatedAt: now)
        guard WorkoutRuntime.store.change({ $0.training = .init(plans: [plan], activePlanID: plan.id, sessions: sessions, concerns: [concern]) }),
              await WorkoutRuntime.store.flushWorkoutChanges() else { throw TrainingError.invalidPlan }
    }
    static func verify() async throws -> String {
        let store = WorkoutRuntime.store
        guard let library = store.data.training, let plan = library.activePlan,
              let exercise = plan.payload.days.first?.exercises.first,
              plan.payload.phase == .loading, (plan.revisions?.isEmpty ?? true), exercise.sets == 3, exercise.reps == "6–8",
              library.sessions.count == 2, library.sessions.allSatisfy({ $0.end != nil && $0.phase == .loading && $0.exercises[0].sets.count == 3 && $0.exercises[0].sets.allSatisfy { $0.done && $0.kg == 40 } }),
              library.concerns?.count == 1, library.concerns?.first?.isActive == true,
              (library.achievements ?? []).isEmpty else { throw TrainingError.invalidPlan }
        let result = TrainingRepProgression.calculate(exercise: exercise, library: library)
        guard result.latest?.status == .atUpper, result.latest?.totalReps == 24, result.comparison?.repDelta == 6,
              result.activeConcernCount == 1, await store.flushWorkoutChanges() else { throw TrainingError.invalidPlan }
        return "Progressione verificata · carichi e avvisi conservati"
    }
}
#endif
