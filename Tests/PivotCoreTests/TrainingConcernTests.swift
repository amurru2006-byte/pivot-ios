import XCTest
@testable import PivotCore

final class TrainingConcernTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_000_000)
    private var first: TrainingExercise { .init(id: "first", name: "Movimento TEST", sets: 1, reps: "6", restSeconds: 60, coachNotes: "", catalogID: "test-catalog") }
    private var second: TrainingExercise { .init(id: "second", name: "Altro movimento TEST", sets: 1, reps: "6", restSeconds: 60, coachNotes: "") }
    private func concern() -> TrainingConcern {
        .init(area: "Zona TEST", intensity: 4, observedAt: now, notes: "Sintomi sintetici", exercises: [.init(first)], createdAt: now, updatedAt: now)
    }
    private func library() -> TrainingLibrary {
        let plan = TrainingPlan(payload: .init(formatVersion: 1, name: "TEST", days: [.init(id: "day", name: "TEST", exercises: [first, second])]))
        var lib = TrainingLibrary(plans: [plan], activePlanID: plan.id)
        let session = lib.makeSession(plan: plan, day: plan.payload.days[0], eventID: nil, now: now)
        lib.sessions = [session]; return lib
    }
    func testConcernSurvivesBackupWithGuidanceLinksAndOptionalIntensity() throws {
        var report = concern(); report.kind = .reportedInjury; report.side = .left
        report.professionalGuidance = "Indicazione riportata TEST"; report.guidanceSource = "Professionista TEST"
        report.originatingSessionID = UUID(); report.exercises.append(.init(second))
        var data = AppData(); data.training = .init(concerns: [report])
        let decoded = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertEqual(decoded.training?.concerns, [report])
        report.intensity = nil; data.training?.concerns = [report]
        XCTAssertNil(try BackupCodec.decode(BackupCodec.encode(data)).training?.concerns?.first?.intensity)
    }
    func testOldBackupWithoutConcernsStillDecodes() throws {
        var data = AppData(); data.training = library()
        let bytes = try BackupCodec.encode(data)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("\"concerns\""))
        let decoded = try BackupCodec.decode(bytes)
        XCTAssertNil(decoded.training?.concerns); XCTAssertEqual(decoded.training?.sessions, data.training?.sessions)
    }
    func testInvalidValuesAndDatesAreRejected() throws {
        var bad = concern(); bad.area = " \n "; XCTAssertFalse(bad.isValid)
        bad = concern(); bad.intensity = 11; XCTAssertFalse(bad.isValid)
        bad = concern(); bad.intensity = -1; XCTAssertFalse(bad.isValid)
        bad = concern(); bad.notes = String(repeating: "x", count: 4001); XCTAssertFalse(bad.isValid)
        bad = concern(); bad.observedAt = now.addingTimeInterval(1); XCTAssertFalse(bad.isValid)
        bad = concern(); bad.resolvedAt = now.addingTimeInterval(-1); XCTAssertFalse(bad.isValid)
        bad = concern(); bad.updatedAt = now.addingTimeInterval(-1); XCTAssertFalse(bad.isValid)
        bad = concern(); bad.exercises.append(.init(first)); XCTAssertFalse(bad.isValid)
        bad = concern(); bad.exercises[0].catalogID = ""; XCTAssertFalse(bad.isValid)
    }
    func testBackupRejectsDuplicateReportsAndInvalidIntensity() throws {
        let report = concern(); var data = AppData(); data.training = .init(concerns: [report, report])
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(data)))
        data.training?.concerns = [report]; data.training?.concerns?[0].intensity = 99
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(data)))
    }
    func testAreaDoesNotAutomaticallyLinkOtherMovements() {
        let report = concern(), lib = TrainingLibrary(concerns: [report])
        XCTAssertEqual(TrainingConcerns.active(for: first, in: lib).count, 1)
        XCTAssertTrue(TrainingConcerns.active(for: second, in: lib).isEmpty)
        var generic = report; generic.exercises = []
        XCTAssertTrue(TrainingConcerns.active(for: first, in: .init(concerns: [generic])).isEmpty)
    }
    func testExplicitLinksApplyToMultipleExercisesAndSameCatalogAcrossPlans() {
        var report = concern(); report.exercises.append(.init(second))
        let lib = TrainingLibrary(concerns: [report])
        XCTAssertEqual(TrainingConcerns.active(for: second, in: lib).map(\.id), [report.id])
        var reimported = first; reimported.id = "new-plan-id"
        XCTAssertEqual(TrainingConcerns.active(for: reimported, in: lib).map(\.id), [report.id])
    }
    func testChangedVariantOrCatalogDoesNotInheritWarning() {
        let lib = TrainingLibrary(concerns: [concern()])
        var different = first; different.catalogID = "other-catalog"
        XCTAssertTrue(TrainingConcerns.active(for: different, in: lib).isEmpty)
        different = first; different.name = "Variante monolaterale TEST"
        XCTAssertTrue(TrainingConcerns.active(for: different, in: lib).isEmpty)
        different = first; different.id = "different-id"; different.catalogID = nil
        XCTAssertTrue(TrainingConcerns.active(for: different, in: lib).isEmpty)
    }
    func testResolvedReportRemainsInHistoryAndCanBeReactivated() throws {
        let original = concern(); var draft = original; draft.resolvedAt = now
        let resolved = try TrainingConcerns.saving(draft, expected: original, in: .init(concerns: [original]), now: now)
        XCTAssertTrue(TrainingConcerns.active(for: first, in: resolved.library).isEmpty)
        XCTAssertEqual(resolved.library.concerns?.count, 1)
        draft = resolved.concern; draft.resolvedAt = nil
        let reopened = try TrainingConcerns.saving(draft, expected: resolved.concern, in: resolved.library, now: now)
        XCTAssertEqual(TrainingConcerns.active(for: first, in: reopened.library).count, 1)
    }
    func testSavingIsAtomicAndDoesNotMutatePlanWorkoutOrAchievements() throws {
        let lib = library(), report = concern()
        let saved = try TrainingConcerns.saving(report, expected: nil, in: lib, now: now)
        XCTAssertNil(lib.concerns)
        XCTAssertEqual(saved.library.plans.first?.payload, lib.plans.first?.payload)
        XCTAssertEqual(saved.library.sessions, lib.sessions); XCTAssertEqual(saved.library.achievements, lib.achievements)
        var invalid = report; invalid.area = ""
        XCTAssertThrowsError(try TrainingConcerns.saving(invalid, expected: nil, in: lib, now: now))
        XCTAssertNil(lib.concerns)
    }
    func testStaleEditorAndDuplicateNewIDCannotOverwriteAnotherVersion() throws {
        let original = concern(); var changed = original; changed.notes = "Versione successiva"
        let lib = TrainingLibrary(concerns: [changed])
        XCTAssertThrowsError(try TrainingConcerns.saving(original, expected: original, in: lib, now: now))
        XCTAssertThrowsError(try TrainingConcerns.saving(changed, expected: nil, in: lib, now: now))
        XCTAssertEqual(lib.concerns?.first?.notes, changed.notes)
    }
    func testEditsPreserveCreationAndOriginWithoutDuplicatingReport() throws {
        var original = concern(); original.originatingSessionID = UUID()
        var draft = original; draft.createdAt = now.addingTimeInterval(50); draft.originatingSessionID = UUID(); draft.notes = "Correzione"
        let saved = try TrainingConcerns.saving(draft, expected: original, in: .init(concerns: [original]), now: now.addingTimeInterval(100))
        XCTAssertEqual(saved.library.concerns?.count, 1)
        XCTAssertEqual(saved.concern.createdAt, original.createdAt)
        XCTAssertEqual(saved.concern.originatingSessionID, original.originatingSessionID)
        XCTAssertEqual(saved.concern.updatedAt, now.addingTimeInterval(100))
    }
    func testDeletingWorkoutKeepsIndependentConcernAndWarning() throws {
        let lib = library(); var report = concern(); report.originatingSessionID = lib.sessions[0].id
        var data = AppData(); data.training = lib; data.training?.concerns = [report]
        let removed = try TrainingHistory.removing(lib.sessions[0], from: data)
        XCTAssertEqual(removed.training?.concerns, [report])
        XCTAssertEqual(TrainingConcerns.active(for: first, in: removed.training!).count, 1)
    }
    func testHealthReportsAreNotAddedToTrainingTextExport() {
        var lib = library(), report = concern(); report.notes = "PRIVATE-SYMPTOM-TEST"; report.professionalGuidance = "PRIVATE-GUIDANCE-TEST"
        lib.concerns = [report]
        let text = TrainingExport.text(lib.sessions[0], library: lib)
        XCTAssertFalse(text.contains(report.notes)); XCTAssertFalse(text.contains(report.professionalGuidance))
    }
}
