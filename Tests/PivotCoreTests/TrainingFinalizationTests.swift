import XCTest
@testable import PivotCore

final class TrainingFinalizationTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 10000)
    private func workout() -> TrainingSession {
        let exercise = TrainingExercise(id: "crunch", name: "Cable Crunch", sets: 2, reps: "10–12", restSeconds: 90, coachNotes: "")
        return .init(planID: UUID(), dayName: "Squat", calendarEventID: "linked-event", start: start,
                     exercises: [.init(exercise: exercise, sets: [.init(number: 1, kg: 20, reps: 12, done: true), .init(number: 2)])])
    }
    func testCompletionSetsEndAndClosesRecoveryWithoutInventingSets() throws {
        var session = workout()
        session.rest = .init(exerciseID: "crunch", setID: session.exercises[0].sets[0].id, seconds: 90, now: start.addingTimeInterval(100))
        let finished = try TrainingFinalization.completed(session, now: start.addingTimeInterval(150))
        XCTAssertEqual(finished.end, start.addingTimeInterval(150)); XCTAssertNil(finished.rest)
        XCTAssertEqual(finished.exercises[0].sets[0].actualRestSeconds, 50)
        XCTAssertTrue(finished.exercises[0].sets[0].done)
        XCTAssertFalse(finished.exercises[0].sets[1].done); XCTAssertNil(finished.exercises[0].sets[1].skipped)
        XCTAssertEqual(finished.id, session.id); XCTAssertEqual(finished.calendarEventID, "linked-event")
        try TrainingLibrary(sessions: [finished]).validate()
        XCTAssertNil(session.end); XCTAssertNotNil(session.rest, "Preparing a snapshot must not mutate the caller")
    }
    func testRepeatedExportKeepsEndAndMeasuredRest() throws {
        var session = workout()
        session.rest = .init(exerciseID: "crunch", setID: session.exercises[0].sets[0].id, seconds: 90, now: start)
        let first = try TrainingFinalization.completed(session, now: start.addingTimeInterval(120))
        let second = try TrainingFinalization.completed(first, now: start.addingTimeInterval(600))
        XCTAssertEqual(second.end, first.end); XCTAssertEqual(second.exercises, first.exercises)
        XCTAssertEqual(second.id, first.id)
    }
    func testManualEndIsPreservedAndUsedForActualRest() throws {
        var session = workout(); session.end = start.addingTimeInterval(100)
        session.rest = .init(exerciseID: "crunch", setID: session.exercises[0].sets[0].id, seconds: 90, now: start.addingTimeInterval(50))
        let finished = try TrainingFinalization.completed(session, now: start.addingTimeInterval(200))
        XCTAssertEqual(finished.end, session.end); XCTAssertEqual(finished.exercises[0].sets[0].actualRestSeconds, 50)
    }
    func testInvalidEndLeavesLiveSessionUntouched() {
        var session = workout()
        session.rest = .init(exerciseID: "crunch", setID: session.exercises[0].sets[0].id, seconds: 90, now: start)
        let original = session
        XCTAssertThrowsError(try TrainingFinalization.completed(session, now: start.addingTimeInterval(-1)))
        XCTAssertEqual(session, original)
        session.end = start.addingTimeInterval(-1)
        XCTAssertThrowsError(try TrainingFinalization.completed(session, now: start.addingTimeInterval(200)))
    }
    func testAccidentalEmptyWorkoutStaysEmptyAndCanBeRecorded() throws {
        var session = workout(); session.exercises[0].sets[0].done = false
        let finished = try TrainingFinalization.completed(session, now: start.addingTimeInterval(1))
        XCTAssertEqual(finished.exercises.flatMap(\.sets).filter(\.done).count, 0)
        try TrainingLibrary(sessions: [finished]).validate()
    }
    func testReportIdentityIsStableAndDoesNotCollideOnSameDay() {
        let directory = URL(fileURLWithPath: "/reports", isDirectory: true)
        var session = workout()
        let first = TrainingReportFiles.url(for: session.id, directory: directory)
        session.dayName = "Nome corretto"; session.start = start.addingTimeInterval(50)
        XCTAssertEqual(TrainingReportFiles.url(for: session.id, directory: directory), first)
        XCTAssertNotEqual(TrainingReportFiles.url(for: UUID(), directory: directory), first)
        XCTAssertEqual(first.deletingLastPathComponent(), directory)
        XCTAssertEqual(first.pathExtension, "pdf")
    }
}
