import XCTest
@testable import PivotCore

final class TrainingCoachOutboxTests: XCTestCase {
    typealias Exchange = TrainingCoachExchange
    typealias Outbox = TrainingCoachOutbox
    private func fixture() -> (TrainingSession, Exchange.Link) {
        let exercise = TrainingExercise(id: "synthetic-press", name: "Synthetic press",
                                        sets: 1, reps: "5", restSeconds: 90, coachNotes: "")
        let set = TrainingSet(number: 1, kg: 90, reps: 5, done: true, kind: .working, isAdditional: false)
        let session = TrainingSession(planID: UUID(), dayName: "Synthetic day", calendarEventID: nil,
                                      start: Date(timeIntervalSince1970: 1800000000),
                                      end: Date(timeIntervalSince1970: 1800001800),
                                      exercises: [.init(exercise: exercise, sets: [set], notes: "PRIVATE-NOTES-MUST-STAY-LOCAL")],
                                      notes: "PRIVATE-NOTES-MUST-STAY-LOCAL", dayID: "synthetic-local-day")
        let link = Exchange.Link(accountID: "synthetic-account", assignmentID: "synthetic-program",
                                 revisionID: "synthetic-prescription", dayID: "synthetic-remote-day",
                                 sourcePlanID: session.planID, sourceDayID: "synthetic-local-day",
                                 exercises: [.init(sourceID: exercise.id, remoteID: "synthetic-remote-exercise",
                                                   loadBasis: .total, sets: [.init(sourceID: set.id, slotID: "slot-1", role: .prescribedWorking)])])
        return (session, link)
    }
    private func snapshot(_ fixture: (TrainingSession, Exchange.Link), revision: Int = 1) throws -> Outbox.Snapshot {
        try .init(preview: Exchange.preview(session: fixture.0, link: fixture.1, accountID: "synthetic-account"), revision: revision)
    }
    private func receipt(_ value: Outbox.Snapshot, outcome: Outbox.Outcome = .verifiedCommitted,
                         remote: String? = "synthetic-remote-workout") throws -> Outbox.Receipt {
        try .init(operation: value.operation, digest: value.digest, outcome: outcome, remoteWorkoutID: remote)
    }
    func testProjectionKeepsActualNinetyAndExcludesPrivateNotes() throws {
        let s = try snapshot(fixture())
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(s.records[0].kg, 90)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("PRIVATE-NOTES"))
        XCTAssertEqual(try s.digest, try s.digest)
    }
    func testSameRevisionIsQueuedOnceAndChangedActualRequiresAnotherRevision() throws {
        var f = fixture(); var box = Outbox()
        let first = try snapshot(f); try box.enqueue(first); try box.enqueue(first)
        XCTAssertEqual(box.entries.count, 1)
        f.0.exercises[0].sets[0].kg = 92.5
        XCTAssertThrowsError(try box.enqueue(snapshot(f)))
    }
    func testQueuedAndWritingDecodedArchivesRequireReconciliation() throws {
        let s = try snapshot(fixture())
        for writing in [false, true] {
            var box = Outbox(); try box.enqueue(s)
            if writing { try box.begin(s.operation) }
            var restored = try JSONDecoder().decode(Outbox.self, from: JSONEncoder().encode(box))
            XCTAssertEqual(restored.entries[0].state, .uncertain)
            XCTAssertThrowsError(try restored.begin(s.operation))
        }
    }
    func testOnlyVerifiedAbsenceAllowsRetry() throws {
        let s = try snapshot(fixture()); var box = Outbox(); try box.enqueue(s); try box.begin(s.operation)
        try box.markUncertain(s.operation)
        try box.reconcile(receipt(s, outcome: .verifiedAbsent, remote: nil))
        XCTAssertEqual(box.entries[0].state, .queued)
        try box.begin(s.operation)
    }
    func testWrongDigestCannotConfirmAnEntry() throws {
        let s = try snapshot(fixture()); var box = Outbox(); try box.enqueue(s); try box.begin(s.operation)
        XCTAssertThrowsError(try box.reconcile(.init(operation: s.operation, digest: String(repeating: "0", count: 64),
                                                   outcome: .verifiedCommitted, remoteWorkoutID: "synthetic-remote")))
        XCTAssertEqual(box.entries[0].state, .writing)
    }
    func testCorrectionCannotStartBeforePreviousRevisionIsReconciled() throws {
        let f = fixture(); var box = Outbox(); try box.enqueue(snapshot(f))
        XCTAssertThrowsError(try box.enqueue(snapshot(f, revision: 2)))
    }
    func testCorrectionTargetsSameRemoteWorkoutAndRejectsDuplicateReceipt() throws {
        var f = fixture(); var box = Outbox(); let first = try snapshot(f)
        try box.enqueue(first); try box.begin(first.operation); try box.reconcile(receipt(first))
        f.0.exercises[0].sets[0].kg = 92.5
        let correction = try snapshot(f, revision: 2); try box.enqueue(correction)
        XCTAssertEqual(box.entries[1].targetRemoteWorkoutID, "synthetic-remote-workout")
        try box.begin(correction.operation)
        XCTAssertThrowsError(try box.reconcile(receipt(correction, remote: "different-workout")))
        XCTAssertEqual(box.entries[1].state, .writing)
        try box.reconcile(receipt(correction))
        try box.validate()
    }
    func testMissingCorrectionTargetCannotBecomeANewWorkout() throws {
        let f = fixture(); var box = Outbox(); let first = try snapshot(f)
        try box.enqueue(first); try box.begin(first.operation); try box.reconcile(receipt(first))
        let correction = try snapshot(f, revision: 2); try box.enqueue(correction); try box.begin(correction.operation)
        XCTAssertThrowsError(try box.reconcile(receipt(correction, outcome: .verifiedAbsent, remote: nil)))
    }
    func testConfirmedRecordCannotBeBlindlySentAgainAfterDecode() throws {
        let s = try snapshot(fixture()); var box = Outbox(); try box.enqueue(s); try box.begin(s.operation)
        try box.reconcile(receipt(s))
        var restored = try JSONDecoder().decode(Outbox.self, from: JSONEncoder().encode(box))
        XCTAssertEqual(restored.entries[0].state, .confirmed)
        XCTAssertThrowsError(try restored.begin(s.operation))
    }
    func testForgedConfirmationWithoutMatchingReceiptIsRejected() throws {
        let s = try snapshot(fixture()); var box = Outbox(); try box.enqueue(s)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(box)) as? [String: Any])
        var entries = try XCTUnwrap(raw["entries"] as? [[String: Any]])
        entries[0]["state"] = "confirmed"; raw["entries"] = entries
        XCTAssertThrowsError(try JSONDecoder().decode(Outbox.self, from: JSONSerialization.data(withJSONObject: raw)))
    }
    func testChangedPayloadInStoredJournalIsRejected() throws {
        let s = try snapshot(fixture()); var box = Outbox(); try box.enqueue(s)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(box)) as? [String: Any])
        var entries = try XCTUnwrap(raw["entries"] as? [[String: Any]])
        var snapshot = try XCTUnwrap(entries[0]["snapshot"] as? [String: Any])
        var records = try XCTUnwrap(snapshot["records"] as? [[String: Any]])
        records[0]["kg"] = 125; snapshot["records"] = records; entries[0]["snapshot"] = snapshot; raw["entries"] = entries
        XCTAssertThrowsError(try JSONDecoder().decode(Outbox.self, from: JSONSerialization.data(withJSONObject: raw)))
    }
    func testUnknownSchemaAndUnboundedRevisionAreRejected() throws {
        XCTAssertThrowsError(try snapshot(fixture(), revision: 0))
        XCTAssertThrowsError(try snapshot(fixture(), revision: 10001))
        XCTAssertThrowsError(try JSONDecoder().decode(Outbox.self, from: Data("{\"schema\":2,\"entries\":[]}".utf8)))
    }
    func testConflictNeverTurnsIntoAQueuedRetry() throws {
        let s = try snapshot(fixture()); var box = Outbox(); try box.enqueue(s); try box.begin(s.operation)
        try box.reconcile(receipt(s, outcome: .conflict, remote: nil))
        XCTAssertEqual(box.entries[0].state, .conflict)
        XCTAssertThrowsError(try box.begin(s.operation))
    }
}
