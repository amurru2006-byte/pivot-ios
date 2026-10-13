#if DEBUG && targetEnvironment(simulator)
import Foundation
@MainActor
enum TrainingHistoryFixture {
    static let sessionID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    static let emptyID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
    static func install() async throws {
        let exercise = TrainingExercise(id: "history-squat", name: "Barbell Squat", sets: 1, reps: "6", restSeconds: 60, coachNotes: "Dati sintetici", catalogID: "Barbell_Squat")
        let day = TrainingDay(id: "history-squat-day", name: "Squat TEST", exercises: [exercise])
        let other = TrainingDay(id: "history-bench-day", name: "Bench TEST", exercises: [exercise])
        let plan = TrainingPlan(payload: .init(formatVersion: 1, name: "Cronologia TEST", days: [day, other]))
        var session = TrainingLibrary().makeSession(plan: plan, day: day, eventID: nil, now: Date().addingTimeInterval(-86400))
        session.id = sessionID; session.end = session.start.addingTimeInterval(600)
        session.exercises[0].sets[0].kg = 60; session.exercises[0].sets[0].reps = 6; session.exercises[0].sets[0].done = true
        var empty = TrainingLibrary().makeSession(plan: plan, day: day, eventID: nil); empty.id = emptyID
        let bench = TrainingLibrary().makeSession(plan: plan, day: other, eventID: nil)
        guard WorkoutRuntime.store.change({ $0.training = .init(plans: [plan], activePlanID: plan.id, sessions: [session, empty, bench]) }),
              await WorkoutRuntime.store.flushWorkoutChanges() else { throw TrainingError.invalidPlan }
    }
    static func verify(deleted: Bool) async throws -> String {
        let store = WorkoutRuntime.store
        guard let library = store.data.training, let plan = library.activePlan,
              library.sessions.contains(where: { $0.dayID == "history-bench-day" }),
              plan.payload.days[0].exercises[0].sets == 1,
              plan.payload.days[0].exercises[0].reps == "6" else { throw TrainingError.invalidPlan }
        if deleted {
            guard !library.sessions.contains(where: { $0.id == sessionID || $0.id == emptyID }) else { throw TrainingError.invalidPlan }
        } else {
            guard let saved = library.sessions.first(where: { $0.id == sessionID }), saved.end != nil, saved.rest == nil,
                  saved.exercises[0].sets[0].kg == 50, saved.exercises[0].sets[0].done,
                  ExerciseProgress.calculate(exerciseID: "history-squat", library: library).bestLoad == 50 else { throw TrainingError.invalidPlan }
        }
        guard await store.flushWorkoutChanges() else { throw TrainingError.invalidPlan }
        return deleted ? "Cronologia verificata · eliminazioni salvate" : "Cronologia verificata · correzione salvata"
    }
}
#endif
