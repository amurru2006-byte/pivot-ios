import XCTest
@testable import PivotCore

final class TrainingCoachExchangeTests: XCTestCase {
    private typealias Exchange = TrainingCoachExchange
    private let start = Date(timeIntervalSince1970: 1800000000)

    private func fixture(sets: [TrainingSet]? = nil, roles: [Exchange.Role]? = nil,
                         duration: Bool = false) -> (TrainingSession, Exchange.Link) {
        let sets = sets ?? [.init(number: 1, kg: 90, reps: 8, done: true, kind: .working, isAdditional: false)]
        let roles = roles ?? sets.map { _ in .prescribedWorking }
        let exercise = TrainingExercise(id: "synthetic-exercise", name: "Synthetic press", sets: 1,
                                        reps: "8", restSeconds: 120, coachNotes: "Synthetic prescription", isometric: duration)
        let log = TrainingExerciseLog(exercise: exercise, sets: sets, notes: "Synthetic exercise note")
        let session = TrainingSession(planID: UUID(), dayName: "Synthetic day", calendarEventID: nil,
                                      start: start, end: start.addingTimeInterval(1800), exercises: [log],
                                      notes: "Synthetic session note", dayID: "synthetic-day")
        let bindings = zip(sets, roles).enumerated().map { index, pair in
            Exchange.SetLink(sourceID: pair.0.id,
                             slotID: [.prescribedWorking, .coachActivation].contains(pair.1) ? "synthetic-slot-\(index)" : nil,
                             role: pair.1)
        }
        let link = Exchange.Link(accountID: "synthetic-account", assignmentID: "synthetic-assignment",
                                 revisionID: "synthetic-revision-1", dayID: "synthetic-remote-day",
                                 sourcePlanID: session.planID, sourceDayID: "synthetic-day",
                                 exercises: [.init(sourceID: exercise.id, remoteID: "synthetic-remote-exercise", loadBasis: .total, sets: bindings)])
        return (session, link)
    }
    private func preview(_ session: TrainingSession, _ link: Exchange.Link) throws -> Exchange.Preview {
        try Exchange.preview(session: session, link: link, accountID: "synthetic-account")
    }
    private func prescription(_ record: Exchange.Record, kg: ClosedRange<Double> = 100...100,
                              revision: String = "synthetic-revision-1", observed: Date? = nil,
                              basis: Exchange.LoadBasis = .total) -> Exchange.Prescription {
        .init(accountID: record.key.accountID, assignmentID: record.key.assignmentID,
              exerciseID: record.remoteExerciseID, slotID: record.slotID!, revisionID: revision,
              observedAt: observed ?? start.addingTimeInterval(-100), loadBasis: basis, kg: kg)
    }

    func testCompletedActualNinetyIsNotReplacedByPrescribedHundred() throws {
        let (session, link) = fixture()
        let record = try preview(session, link).records[0]
        let old = prescription(record)
        let review = try Exchange.review(record: record, previous: old, current: nil, sessionEndedAt: session.end!)
        XCTAssertEqual(record.kg, 90)
        XCTAssertEqual(review.previous.kg, 100...100)
        XCTAssertEqual(review.actualKG, 90)
        XCTAssertEqual(review.relationToPrevious, .below)
        XCTAssertEqual(review.revisionStatus, .notChecked)
    }
    func testPreviewCannotClaimSendingOrSynchronization() throws {
        let (session, link) = fixture()
        XCTAssertFalse(try preview(session, link).canSend)
    }
    func testPlaceholderOnUnperformedSetNeverBecomesActual() throws {
        let (session, link) = fixture(sets: [.init(number: 1, kg: 100, reps: 8, toFailure: true, isAdditional: false)])
        let record = try preview(session, link).records[0]
        XCTAssertEqual(record.status, .notPerformed)
        XCTAssertNil(record.kg); XCTAssertNil(record.reps); XCTAssertFalse(record.toFailure)
    }
    func testSkippedSetKeepsItsSlotWithoutPretendingCompletion() throws {
        let (session, link) = fixture(sets: [.init(number: 1, kg: 100, reps: 8, isAdditional: false, skipped: true)])
        let record = try preview(session, link).records[0]
        XCTAssertEqual(record.status, .skipped)
        XCTAssertEqual(record.slotID, "synthetic-slot-0")
        XCTAssertNil(record.kg); XCTAssertNil(record.reps)
    }
    func testPersonalWarmupExcludedButCoachActivationRetained() throws {
        let (session, link) = fixture(sets: [
            .init(number: 1, kg: 20, reps: 8, done: true, kind: .warmup, isAdditional: true),
            .init(number: 2, kg: 0, reps: 10, done: true, kind: .warmup, isAdditional: true),
            .init(number: 3, kg: 90, reps: 8, done: true, kind: .working, isAdditional: false),
        ], roles: [.personalWarmup, .coachActivation, .prescribedWorking])
        let result = try preview(session, link)
        XCTAssertEqual(result.excludedPersonalWarmups, [session.exercises[0].sets[0].id])
        XCTAssertEqual(result.records.map(\.role), [.coachActivation, .prescribedWorking])
        XCTAssertEqual(result.records[0].slotID, "synthetic-slot-1")
    }
    func testExtraBackoffAndFailureRemainOneSeparateRecord() throws {
        let (session, link) = fixture(sets: [
            .init(number: 1, kg: 90, reps: 8, done: true, isAdditional: false),
            .init(number: 2, kg: 70, reps: 12, done: true, kind: .backoff, toFailure: true, isAdditional: true),
        ], roles: [.prescribedWorking, .extra])
        let records = try preview(session, link).records
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[1].role, .extra); XCTAssertEqual(records[1].kind, .backoff)
        XCTAssertNil(records[1].slotID); XCTAssertTrue(records[1].toFailure)
        XCTAssertEqual(records[1].kg, 70)
    }
    func testExtraCannotOverwritePrescribedSlot() {
        let (session, link) = fixture(sets: [.init(number: 1, kg: 90, reps: 8, done: true, isAdditional: true)])
        XCTAssertThrowsError(try preview(session, link))
    }
    func testWarmupCannotBeSilentlyTreatedAsWorking() {
        let (session, link) = fixture(sets: [.init(number: 1, kg: 20, reps: 8, done: true, kind: .warmup)])
        XCTAssertThrowsError(try preview(session, link))
    }
    func testMissingOrDuplicateBindingsAreRejected() {
        let (session, link) = fixture()
        let exercise = link.exercises[0]
        for sets in [[], exercise.sets + exercise.sets] {
            let invalid = Exchange.Link(accountID: link.accountID, assignmentID: link.assignmentID,
                                        revisionID: link.revisionID, dayID: link.dayID, sourcePlanID: link.sourcePlanID,
                                        sourceDayID: link.sourceDayID,
                                        exercises: [.init(sourceID: exercise.sourceID, remoteID: exercise.remoteID, loadBasis: .total, sets: sets)])
            XCTAssertThrowsError(try preview(session, invalid))
        }
    }
    func testAccountPlanAndDayCannotBeMatchedByName() {
        let (session, link) = fixture()
        XCTAssertThrowsError(try Exchange.preview(session: session, link: link, accountID: "different-synthetic-account"))
        var changed = session; changed.planID = UUID()
        XCTAssertThrowsError(try preview(changed, link))
        changed = session; changed.dayID = "different-synthetic-day"
        XCTAssertThrowsError(try preview(changed, link))
    }
    func testUnfinishedSessionIsNotPreparedForSubmission() {
        var (session, link) = fixture(); session.end = nil
        XCTAssertThrowsError(try preview(session, link))
    }
    func testInvalidCompletedMeasurementIsRejected() {
        for weight in [Double.nan, Double.infinity, -1, 2001] {
            let (session, link) = fixture(sets: [.init(number: 1, kg: weight, reps: 8, done: true, isAdditional: false)])
            XCTAssertThrowsError(try preview(session, link))
        }
    }
    func testDurationAndSidesAreNotConvertedToReps() throws {
        let (session, link) = fixture(sets: [.init(number: 1, done: true, durationSeconds: 30, isAdditional: false)], duration: true)
        let record = try preview(session, link).records[0]
        XCTAssertEqual(record.durationSeconds, 30); XCTAssertNil(record.reps); XCTAssertNil(record.kg)
    }
    func testRevisionComparisonRequiresObservationAfterWorkout() throws {
        let (session, link) = fixture()
        let record = try preview(session, link).records[0]
        let old = prescription(record)
        let stale = prescription(record, observed: start)
        XCTAssertEqual(try Exchange.review(record: record, previous: old, current: stale, sessionEndedAt: session.end!).revisionStatus, .notChecked)
        let fresh = prescription(record, observed: session.end!)
        XCTAssertEqual(try Exchange.review(record: record, previous: old, current: fresh, sessionEndedAt: session.end!).revisionStatus, .unchanged)
    }
    func testCoachUpdateIsVisibleWithoutRewritingRecordedPrescription() throws {
        let (session, link) = fixture()
        let record = try preview(session, link).records[0]
        let old = prescription(record)
        let current = prescription(record, kg: 95...95, revision: "synthetic-revision-2", observed: session.end!)
        let result = try Exchange.review(record: record, previous: old, current: current, sessionEndedAt: session.end!)
        XCTAssertEqual(result.revisionStatus, .updated)
        XCTAssertEqual(result.previous.kg, 100...100); XCTAssertEqual(result.current?.kg, 95...95)
        XCTAssertEqual(result.actualKG, 90)
    }
    func testRangeIsPreservedInsteadOfChoosingItsUpperBound() throws {
        let (session, link) = fixture()
        let record = try preview(session, link).records[0]
        let result = try Exchange.review(record: record, previous: prescription(record, kg: 85...95), current: nil, sessionEndedAt: session.end!)
        XCTAssertEqual(result.previous.kg, 85...95)
        XCTAssertEqual(result.relationToPrevious, .within)
    }
    func testDifferentLoadBasisIsNotComparedOrConverted() throws {
        let (session, link) = fixture()
        let record = try preview(session, link).records[0]
        let result = try Exchange.review(record: record, previous: prescription(record, basis: .perHand), current: nil, sessionEndedAt: session.end!)
        XCTAssertEqual(result.relationToPrevious, .notComparable)
    }
    func testRetryIdentityIsStableAndCorrectionDoesNotCreateAnotherKey() throws {
        var (session, link) = fixture()
        let first = try preview(session, link)
        XCTAssertEqual(first, try preview(session, link))
        session.exercises[0].sets[0].kg = 92.5
        let correction = try preview(session, link)
        XCTAssertEqual(first.records[0].key, correction.records[0].key)
        XCTAssertEqual(correction.records[0].kg, 92.5)
    }
    func testPreviewPreservesNotesWithoutChangingBackupOrTrainingModels() throws {
        let (session, link) = fixture()
        let library = TrainingLibrary(sessions: [session])
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(library)
        let result = try preview(session, link)
        XCTAssertEqual(result.exerciseNotes[session.exercises[0].id], "Synthetic exercise note")
        XCTAssertEqual(result.sessionNote, "Synthetic session note")
        XCTAssertEqual(before, try encoder.encode(library))
        let restored = try JSONDecoder().decode(TrainingLibrary.self, from: before)
        XCTAssertEqual(restored.sessions, library.sessions)
    }
    func testContradictoryCompletedSkippedSetIsRejected() {
        let (session, link) = fixture(sets: [.init(number: 1, kg: 90, reps: 8, done: true, skipped: true)])
        XCTAssertThrowsError(try preview(session, link))
    }
}
