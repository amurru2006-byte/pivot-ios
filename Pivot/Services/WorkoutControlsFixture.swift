#if DEBUG && targetEnvironment(simulator)
import Foundation
@MainActor
enum WorkoutControlsFixture {
    static func verify() async throws {
        let store = WorkoutRuntime.store
        guard !store.isLoading, !store.locked else { throw TrainingError.invalidPlan }
        let bench = TrainingExercise(id: "controls-bench", name: "Bench Press", sets: 2, reps: "6", restSeconds: 0, coachNotes: "")
        var hold = TrainingExercise(id: "controls-hold", name: "Copenhagen Plank", sets: 1, reps: "25 s per lato", restSeconds: 0, coachNotes: "")
        hold.isometric = true; hold.separateSides = true; hold.weightedHold = true
        let plan = TrainingPlan(payload: .init(formatVersion: 1, name: "TEST controlli", days: [.init(id: "controls-day", name: "TEST", exercises: [bench, hold])]))
        var session = TrainingLibrary().makeSession(plan: plan, day: plan.payload.days[0], eventID: nil)
        session.exercises[0].sets[0].kg = 70; session.exercises[0].sets[0].reps = 5
        session.exercises[0].sets.append(TrainingSet(number: 3, kg: 35, reps: 8, kind: .warmup, loadFraction: 0.5))
        guard store.change({ $0.training = TrainingLibrary(plans: [plan], activePlanID: plan.id, sessions: [session]) }) else { throw TrainingError.invalidPlan }
        let id = session.id.uuidString, set = session.exercises[0].sets[0].id.uuidString
        try await WorkoutRuntime.perform(sessionID: id, setID: set, action: "kg+")
        try await WorkoutRuntime.perform(sessionID: id, setID: set, action: "reps+")
        let warmup = session.exercises[0].sets[2].id.uuidString
        try await WorkoutRuntime.perform(sessionID: id, setID: warmup, action: "kg+")
        guard store.data.training?.sessions[0].exercises[0].sets[2].kg == 40 else { throw TrainingError.invalidPlan }
        try await WorkoutRuntime.perform(sessionID: id, setID: set, action: "kg+")
        guard store.data.training?.sessions[0].exercises[0].sets[2].kg == 42.5 else { throw TrainingError.invalidPlan }
        try await WorkoutRuntime.perform(sessionID: id, setID: set, action: "kg-")
        guard store.data.training?.sessions[0].exercises[0].sets[2].kg == 40 else { throw TrainingError.invalidPlan }
        try await WorkoutRuntime.perform(sessionID: id, setID: set, action: "done")
        try await WorkoutRuntime.perform(sessionID: id, setID: set, action: "done") // idempotent
        guard let current = store.data.training?.sessions.first(where: { $0.id == session.id }),
              current.exercises[0].sets[0].kg == 72.5, current.exercises[0].sets[0].reps == 6,
              current.exercises[0].sets[0].done, current.rest == nil else { throw TrainingError.invalidPlan }
        session = current
        session.rest = .init(exerciseID: bench.id, setID: session.exercises[0].sets[0].id, seconds: 0)
        session.updatedAt = Date()
        guard store.saveTraining(session, tips: [:], event: nil) else { throw TrainingError.invalidPlan }
        try await WorkoutRuntime.perform(sessionID: id, setID: set, action: "pause")
        guard store.data.training?.sessions[0].rest?.deadline == nil else { throw TrainingError.invalidPlan }
        try await WorkoutRuntime.perform(sessionID: id, setID: set, action: "pause")
        try await WorkoutRuntime.perform(sessionID: id, setID: set, action: "reset")
        try await WorkoutRuntime.perform(sessionID: id, setID: set, action: "next")
        guard store.data.training?.sessions[0].rest == nil,
              store.data.training?.sessions[0].exercises[0].sets[0].actualRestSeconds != nil else { throw TrainingError.invalidPlan }
        let holdID = session.exercises[1].sets[0].id.uuidString
        try await WorkoutRuntime.perform(sessionID: id, setID: holdID, action: "left+")
        try await WorkoutRuntime.perform(sessionID: id, setID: holdID, action: "right+")
        try await WorkoutRuntime.perform(sessionID: id, setID: holdID, action: "kg+")
        try await WorkoutRuntime.perform(sessionID: id, setID: holdID, action: "done")
        guard let final = store.data.training?.sessions[0].exercises[1].sets[0], final.done,
              final.leftSeconds == 1, final.rightSeconds == 1, final.kg == 2.5,
              await store.flushWorkoutChanges() else { throw TrainingError.invalidPlan }
    }
}
#endif
