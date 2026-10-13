import XCTest
@testable import PivotCore

final class TrainingPhaseTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_000_000)
    private var exercise: TrainingExercise { .init(id: "phase-test", name: "Movimento TEST", sets: 1, reps: "6", restSeconds: 60, coachNotes: "") }
    private func plan(_ phase: TrainingPhase? = nil, dayPhase: TrainingPhase? = nil) -> TrainingPlan {
        .init(payload: .init(formatVersion: 1, name: "Fasi TEST", days: [.init(id: "day", name: "Giornata TEST", exercises: [exercise], phase: dayPhase)], phase: phase), importedAt: now)
    }
    private func session(_ plan: TrainingPlan) -> TrainingSession {
        var value = TrainingLibrary().makeSession(plan: plan, day: plan.payload.days[0], eventID: nil, now: now)
        value.updatedAt = now; return value
    }
    func testMissingPhaseRemainsUnknown() {
        let p = plan()
        XCTAssertNil(TrainingPhase.resolved(plan: p.payload, day: p.payload.days[0]))
        XCTAssertNil(session(p).phase)
    }
    func testEveryPlanPhaseIsInheritedAndCapturedByNewSessions() {
        for phase in TrainingPhase.allCases {
            let p = plan(phase)
            XCTAssertEqual(TrainingPhase.resolved(plan: p.payload, day: p.payload.days[0]), phase)
            XCTAssertEqual(session(p).phase, phase)
        }
    }
    func testDayOverrideTakesPriorityAndCanExistWithoutPlanPhase() {
        for inherited in [TrainingPhase.loading, .deload] {
            let p = plan(inherited, dayPhase: .returning)
            XCTAssertEqual(session(p).phase, .returning)
        }
        XCTAssertEqual(session(plan(dayPhase: .deload)).phase, .deload)
    }
    func testRevisionChangesFutureContextWithoutRewritingWorkoutOrLoads() throws {
        let original = plan(.loading)
        var old = session(original); old.end = now.addingTimeInterval(600)
        old.exercises[0].sets[0].kg = 40; old.exercises[0].sets[0].reps = 6; old.exercises[0].sets[0].done = true
        var library = TrainingLibrary(plans: [original], activePlanID: original.id, sessions: [old])
        var next = original.payload; next.phase = .deload
        try TrainingEdits.revise(planID: original.id, payload: next, note: "Contesto TEST", library: &library, now: now)
        XCTAssertEqual(library.sessions, [old])
        XCTAssertEqual(library.plans[0].revisions?.first?.payload.phase, .loading)
        let future = library.makeSession(plan: library.plans[0], day: next.days[0], eventID: nil, now: now.addingTimeInterval(86400))
        XCTAssertEqual(future.phase, .deload)
        XCTAssertEqual(future.exercises[0].sets[0].kg, 40) // No invented percentage reduction.
        XCTAssertFalse(future.exercises[0].sets[0].done)
        XCTAssertEqual(next.days[0].exercises, original.payload.days[0].exercises)
    }
    func testBackupPreservesPlanDayAndRecordedPhaseIndependently() throws {
        let p = plan(.loading, dayPhase: .returning)
        var saved = session(p); saved.phase = .deload
        var data = AppData(); data.training = .init(plans: [p], activePlanID: p.id, sessions: [saved])
        let restored = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertEqual(restored.training?.plans.first?.payload.phase, .loading)
        XCTAssertEqual(restored.training?.plans.first?.payload.days[0].phase, .returning)
        XCTAssertEqual(restored.training?.sessions, [saved])
    }
    func testLegacyBackupDoesNotInferRecordedPhaseFromCurrentPlan() throws {
        let current = plan(.deload)
        var legacy = session(current); legacy.phase = nil
        var data = AppData(); data.training = .init(plans: [current], activePlanID: current.id, sessions: [legacy])
        let restored = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertNil(restored.training?.sessions.first?.phase)
        XCTAssertEqual(restored.training?.plans.first?.payload.phase, .deload)
    }
    func testOlderTrainingPayloadAndSessionDecodeWithoutNewField() throws {
        let p = plan()
        let payloadBytes = try JSONEncoder().encode(p.payload)
        XCTAssertFalse(String(decoding: payloadBytes, as: UTF8.self).contains("\"phase\""))
        XCTAssertNil(try JSONDecoder().decode(TrainingPlanPayload.self, from: payloadBytes).phase)
        let bytes = try JSONEncoder().encode(session(p))
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("\"phase\""))
        XCTAssertNil(try JSONDecoder().decode(TrainingSession.self, from: bytes).phase)
    }
    func testUnknownPhaseIsRejectedRatherThanDefaultedToLoading() throws {
        let p = plan(.loading)
        let bytes = try JSONEncoder().encode(p.payload)
        let bad = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "\"loading\"", with: "\"unsupported-phase\"")
        XCTAssertThrowsError(try JSONDecoder().decode(TrainingPlanPayload.self, from: Data(bad.utf8)))
    }
    func testTrainingPayloadBlockKeepsDeclaredContext() throws {
        let p = plan(.loading, dayPhase: .deload)
        let decoded = try TrainingPDFFormat.parse(TrainingPDFFormat.encodedBlock(p.payload))
        XCTAssertEqual(decoded, p.payload)
    }
    func testFinishKeepsPhaseAndDoesNotAddWork() throws {
        let saved = session(plan(.returning))
        let finished = try TrainingFinalization.completed(saved, now: now.addingTimeInterval(600))
        XCTAssertEqual(finished.phase, .returning)
        XCTAssertEqual(finished.exercises, saved.exercises)
    }
    func testReplacingExerciseDoesNotOverwriteDeclaredContext() throws {
        var saved = session(plan(.deload))
        var replacement = exercise; replacement.id = "replacement"; replacement.name = "Altro movimento TEST"
        try TrainingEdits.replace(in: &saved, exerciseID: exercise.id, with: replacement, library: .init())
        XCTAssertEqual(saved.phase, .deload)
    }
    func testRestoringPlanPhaseLeavesExistingSessionsUnchanged() throws {
        let original = plan(.loading)
        let recorded = session(original)
        var library = TrainingLibrary(plans: [original], activePlanID: original.id, sessions: [recorded])
        var next = original.payload; next.phase = .returning
        try TrainingEdits.revise(planID: original.id, payload: next, note: "TEST", library: &library, now: now)
        try TrainingEdits.revise(planID: original.id, payload: original.payload, note: "Ripristino TEST", library: &library, now: now)
        XCTAssertEqual(library.plans[0].payload.phase, .loading)
        XCTAssertEqual(library.sessions, [recorded])
        XCTAssertEqual(library.plans[0].revisions?.last?.payload.phase, .returning)
    }
    func testDeclaringReturnDoesNotResolveReportsOrAuthorizeLoads() {
        let p = plan(.returning)
        let report = TrainingConcern(area: "Zona TEST", observedAt: now, exercises: [.init(exercise)], createdAt: now, updatedAt: now)
        let library = TrainingLibrary(plans: [p], activePlanID: p.id, concerns: [report])
        let next = library.makeSession(plan: p, day: p.payload.days[0], eventID: nil, now: now)
        XCTAssertEqual(next.phase, .returning)
        XCTAssertEqual(TrainingConcerns.active(for: exercise, in: library).map(\.id), [report.id])
        XCTAssertNil(next.exercises[0].sets[0].kg)
        XCTAssertFalse(next.exercises[0].sets[0].done)
    }
    func testExerciseHistoryKeepsPhaseWithoutChangingMetrics() {
        var first = session(plan(.loading)); first.end = now.addingTimeInterval(600)
        first.exercises[0].sets[0].kg = 40; first.exercises[0].sets[0].reps = 6; first.exercises[0].sets[0].done = true
        var second = first; second.id = UUID(); second.start = now.addingTimeInterval(86400)
        second.end = second.start.addingTimeInterval(600); second.phase = .deload; second.exercises[0].sets[0].kg = 30
        let progress = ExerciseProgress.calculate(exerciseID: exercise.id, library: .init(sessions: [first, second]))
        XCTAssertEqual(progress.performances.map(\.phase), [.loading, .deload])
        XCTAssertEqual(progress.performances.map(\.bestLoad), [40, 30])
        XCTAssertEqual(progress.performances.map(\.volume), [240, 180])
        XCTAssertEqual(progress.bestLoad, 40)
    }
    func testTextExportUsesRecordedPhaseAndExcludesPersonalReports() {
        let p = plan(.deload)
        var saved = session(p); saved.phase = .returning
        let report = TrainingConcern(area: "PRIVATE-AREA-TEST", notes: "PRIVATE-SYMPTOM-TEST")
        let library = TrainingLibrary(plans: [p], activePlanID: p.id, sessions: [saved], concerns: [report])
        let text = TrainingExport.text(saved, library: library)
        XCTAssertTrue(text.contains("Fase dichiarata: Recupero / rientro"))
        XCTAssertFalse(text.contains("Fase dichiarata: Scarico"))
        XCTAssertFalse(text.contains(report.area)); XCTAssertFalse(text.contains(report.notes))
        saved.phase = nil
        XCTAssertTrue(TrainingExport.text(saved, library: library).contains("Fase dichiarata: non dichiarata"))
    }
}
