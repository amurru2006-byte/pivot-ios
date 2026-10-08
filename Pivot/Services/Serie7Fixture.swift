#if DEBUG && targetEnvironment(simulator)
import Foundation
@MainActor
enum Serie7Fixture {
    static let sessionID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    static let setID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    static func install() throws {
        let bench = TrainingExercise(id: "s7-bench", name: "Bench Press", sets: 2, reps: "4–6", restSeconds: 0, coachNotes: "Dati sintetici per test")
        let plank = TrainingExercise(id: "s7-plank", name: "Plank", sets: 1, reps: "30 s", restSeconds: 0, coachNotes: "")
        let day = TrainingDay(id: "s7-day", name: "Serie 7 TEST", exercises: [bench, plank])
        let plan = TrainingPlan(payload: .init(formatVersion: 1, name: "Serie 7 TEST", days: [day]))
        var session = TrainingLibrary().makeSession(plan: plan, day: day, eventID: nil)
        session.id = sessionID; session.exercises[0].sets[0].id = setID
        session.exercises[0].sets[0].kg = 50; session.exercises[0].sets[0].reps = 6
        var earlier = session; earlier.id = UUID(); earlier.start = session.start.addingTimeInterval(-86400)
        earlier.end = earlier.start.addingTimeInterval(100)
        earlier.exercises = [.init(exercise: bench, sets: [.init(number: 1, kg: 40, reps: 6, done: true)])]
        guard WorkoutRuntime.store.change({ $0.strengthProfile = nil; $0.training = .init(plans: [plan], activePlanID: plan.id, sessions: [earlier,session]) }) else { throw TrainingError.invalidPlan }
    }
}
#endif
