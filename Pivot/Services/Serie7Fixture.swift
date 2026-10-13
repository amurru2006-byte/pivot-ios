#if DEBUG && targetEnvironment(simulator)
import Foundation
@MainActor
enum Serie7Fixture {
    static let sessionID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    static let setID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    static func installRecovery() async throws {
        let exercises = (1...8).map { index in
            TrainingExercise(id: "recovery-\(index)", name: index == 8 ? "Cable Crunch" : "Esercizio \(index)", sets: 2, reps: "10–12", restSeconds: 90, coachNotes: "Dati sintetici")
        }
        let day = TrainingDay(id: "recovery-day", name: "Recupero TEST", exercises: exercises)
        let plan = TrainingPlan(payload: .init(formatVersion: 1, name: "Recupero TEST", days: [day]))
        var session = TrainingLibrary().makeSession(plan: plan, day: day, eventID: nil)
        session.id = sessionID
        for index in 0..<7 { TrainingCompletion.skipExercise(in: &session, at: index) }
        for index in session.exercises[7].sets.indices {
            session.exercises[7].sets[index].kg = 20; session.exercises[7].sets[index].reps = 12
        }
        session.exercises[7].sets[0].id = setID
        guard WorkoutRuntime.store.change({ $0.training = .init(plans: [plan], activePlanID: plan.id, sessions: [session]) }),
              await WorkoutRuntime.store.flushWorkoutChanges() else { throw TrainingError.invalidPlan }
    }
    static func install(withRank: Bool = false) async throws {
        let bench = TrainingExercise(id: "s7-bench", name: "Bench Press", sets: 2, reps: "4–6", restSeconds: 0, coachNotes: "Dati sintetici per test")
        let plank = TrainingExercise(id: "s7-plank", name: "Plank", sets: 1, reps: "30 s", restSeconds: 0, coachNotes: "")
        let day = TrainingDay(id: "s7-day", name: "Serie 7 TEST", exercises: [bench, plank])
        let plan = TrainingPlan(payload: .init(formatVersion: 1, name: "Serie 7 TEST", days: [day]))
        var session = TrainingLibrary().makeSession(plan: plan, day: day, eventID: nil)
        session.id = sessionID; session.exercises[0].sets[0].id = setID
        session.exercises[0].sets[0].kg = withRank ? 75 : 50; session.exercises[0].sets[0].reps = 6
        var earlier = session; earlier.id = UUID(); earlier.start = session.start.addingTimeInterval(-86400)
        earlier.end = earlier.start.addingTimeInterval(100)
        earlier.exercises = [.init(exercise: bench, sets: [.init(number: 1, kg: 40, reps: 6, done: true)])]
        guard WorkoutRuntime.store.change({
            $0.strengthProfile = withRank ? .init(birthDate: ISO8601DateFormatter().date(from: "2006-01-01T12:00:00Z"), bodyMassKG: 75, heightCM: 175, referenceSex: .male) : nil
            $0.training = .init(plans: [plan], activePlanID: plan.id, sessions: [earlier,session])
        }) else { throw TrainingError.invalidPlan }
        // XCUIApplication.open can cold-launch the app immediately after this
        // button is tapped. Only report readiness after the fixture is durable.
        guard await WorkoutRuntime.store.flushWorkoutChanges() else { throw TrainingError.invalidPlan }
    }
}
#endif
