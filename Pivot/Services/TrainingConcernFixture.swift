#if DEBUG && targetEnvironment(simulator)
import Foundation
@MainActor
enum TrainingConcernFixture {
    static func install() async throws {
        let first = TrainingExercise(id: "concern-first", name: "Primo movimento TEST", sets: 1, reps: "6", restSeconds: 60, coachNotes: "Dati sintetici")
        let second = TrainingExercise(id: "concern-second", name: "Secondo movimento TEST", sets: 1, reps: "6", restSeconds: 60, coachNotes: "Dati sintetici")
        let plan = TrainingPlan(payload: .init(formatVersion: 1, name: "Segnalazioni TEST", days: [.init(id: "concern-day", name: "Movimenti TEST", exercises: [first, second])]))
        guard WorkoutRuntime.store.change({ $0.training = .init(plans: [plan], activePlanID: plan.id) }),
              await WorkoutRuntime.store.flushWorkoutChanges() else { throw TrainingError.invalidPlan }
    }
    static func verify(kind: TrainingConcernKind, deleted: Bool = false) async throws -> String {
        let store = WorkoutRuntime.store
        guard let library = store.data.training, library.sessions.isEmpty,
              library.achievements?.isEmpty ?? true,
              let plan = library.activePlan, plan.payload.days[0].exercises.count == 2,
              plan.payload.days[0].exercises.allSatisfy({ $0.sets == 1 && $0.reps == "6" }) else { throw TrainingError.invalidPlan }
        if deleted {
            guard library.concerns?.isEmpty == true,
                  plan.payload.days[0].exercises.allSatisfy({ TrainingConcerns.active(for: $0, in: library).isEmpty }),
                  await store.flushWorkoutChanges() else { throw TrainingError.invalidPlan }
            return "Eliminazione verificata · allenamenti conservati"
        }
        guard let report = library.concerns?.first, library.concerns?.count == 1,
              report.kind == kind, report.area == "Zona TEST", report.exercises.count == 2,
              TrainingConcerns.active(for: plan.payload.days[0].exercises[0], in: library).count == (report.isActive ? 1 : 0),
              TrainingConcerns.active(for: plan.payload.days[0].exercises[1], in: library).count == (report.isActive ? 1 : 0),
              await store.flushWorkoutChanges() else { throw TrainingError.invalidPlan }
        return report.isActive ? "Segnalazione verificata · due movimenti" : "Segnalazione verificata · storico conservato"
    }
}
#endif
