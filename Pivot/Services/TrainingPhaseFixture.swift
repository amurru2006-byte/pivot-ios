#if DEBUG && targetEnvironment(simulator)
import Foundation
@MainActor
enum TrainingPhaseFixture {
    static let oldID = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
    static func install() async throws {
        let exercise = TrainingExercise(id: "phase-exercise", name: "Movimento TEST", sets: 1, reps: "6", restSeconds: 60, coachNotes: "Dati sintetici")
        let day = TrainingDay(id: "phase-day", name: "Giornata TEST", exercises: [exercise])
        let plan = TrainingPlan(payload: .init(formatVersion: 1, name: "Fasi TEST", days: [day], phase: .loading))
        var old = TrainingLibrary().makeSession(plan: plan, day: day, eventID: nil, now: Date().addingTimeInterval(-86400))
        old.id = oldID; old.end = old.start.addingTimeInterval(600)
        old.exercises[0].sets[0].kg = 40; old.exercises[0].sets[0].reps = 6; old.exercises[0].sets[0].done = true
        guard WorkoutRuntime.store.change({ $0.training = .init(plans: [plan], activePlanID: plan.id, sessions: [old]) }),
              await WorkoutRuntime.store.flushWorkoutChanges() else { throw TrainingError.invalidPlan }
    }
    static func verify() async throws -> String {
        let store = WorkoutRuntime.store
        guard let library = store.data.training, let plan = library.activePlan,
              plan.payload.phase == .deload, plan.payload.days[0].phase == .returning,
              plan.revisions?.count == 1, plan.revisions?.first?.payload.phase == .loading,
              plan.payload.days[0].exercises[0].sets == 1, plan.payload.days[0].exercises[0].reps == "6",
              let old = library.sessions.first(where: { $0.id == oldID }), old.phase == .loading,
              old.exercises[0].sets[0].kg == 40, old.exercises[0].sets[0].done,
              let current = library.sessions.first(where: { $0.id != oldID }), current.phase == .returning,
              current.end == nil, current.exercises[0].sets[0].kg == 40, !current.exercises[0].sets[0].done,
              library.sessions.count == 2, await store.flushWorkoutChanges() else { throw TrainingError.invalidPlan }
        return "Fasi verificate · storico e carichi conservati"
    }
}
#endif
