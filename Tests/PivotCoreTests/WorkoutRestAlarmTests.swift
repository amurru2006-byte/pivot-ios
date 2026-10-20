import XCTest
@testable import PivotCore

final class WorkoutRestAlarmTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func session() -> TrainingSession {
        var value = TrainingSession(planID: UUID(), dayName: "Allenamento audio QA", start: now, exercises: [])
        value.rest = .init(exerciseID: "exercise-qa", setID: UUID(), seconds: 120, now: now)
        return value
    }
    private var enabled: WorkoutRestAudioSettings { .init(enabled: true, volumeStep: 5) }
    func testLegacySettingsDoNotAutomaticallyEnableAlarms() throws {
        let data = AppData()
        let legacy = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertNil(legacy.settings.workoutRestAudio)
        XCTAssertEqual(WorkoutRestAlarm.decision(session: session(), settings: .init(), now: now), .cancel)
        let restored = enabled.requiringDeviceActivation
        XCTAssertFalse(restored.enabled)
        XCTAssertEqual(restored.volumeStep, enabled.volumeStep)
        XCTAssertEqual(WorkoutRestAlarm.decision(session: session(), settings: restored, now: now), .cancel,
                       "An imported workout autosave cannot activate an audible alarm")
    }
    func testOnlyFutureRestIsScheduledAtItsActualDeadline() {
        let session = session()
        XCTAssertEqual(WorkoutRestAlarm.decision(session: session, settings: enabled, now: now), .schedule(now.addingTimeInterval(120)))
    }
    func testExpiryDoesNotAutoStopOrRescheduleManualAlarm() {
        let session = session()
        XCTAssertEqual(WorkoutRestAlarm.decision(session: session, settings: enabled, now: now.addingTimeInterval(120)), .keepExisting)
        XCTAssertEqual(WorkoutRestAlarm.decision(session: session, settings: enabled, now: now.addingTimeInterval(300)), .keepExisting)
    }
    func testPauseResetNextAndFinishHaveCoherentDecisions() {
        var value = session()
        value.rest?.togglePause(now: now.addingTimeInterval(10))
        XCTAssertEqual(WorkoutRestAlarm.decision(session: value, settings: enabled, now: now), .cancel)
        value.rest?.togglePause(now: now.addingTimeInterval(20))
        XCTAssertEqual(WorkoutRestAlarm.decision(session: value, settings: enabled, now: now), .schedule(now.addingTimeInterval(130)))
        value.rest?.resetCountdown(now: now.addingTimeInterval(30))
        XCTAssertEqual(WorkoutRestAlarm.decision(session: value, settings: enabled, now: now), .schedule(now.addingTimeInterval(150)))
        value.rest = nil
        XCTAssertEqual(WorkoutRestAlarm.decision(session: value, settings: enabled, now: now), .cancel)
        value = session(); value.end = now.addingTimeInterval(60)
        XCTAssertEqual(WorkoutRestAlarm.decision(session: value, settings: enabled, now: now), .cancel)
    }
    func testAlarmNamespaceDoesNotOwnProbeOrOtherAppAlarmFeatures() {
        let sessionID = UUID()
        let id = WorkoutRestAlarm.id(sessionID: sessionID)
        XCTAssertEqual(id, WorkoutRestAlarm.id(sessionID: sessionID))
        XCTAssertTrue(WorkoutRestAlarm.owns(id))
        XCTAssertFalse(WorkoutRestAlarm.owns(UUID(uuidString: "DED90620-560D-459B-9075-C387D4960BC7")!))
    }
    func testRestoredIdentifierCollisionIsDetectedBeforeAnyCancellation() {
        var a = session(), b = session()
        a.id = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        b.id = UUID(uuidString: "66666666-2222-4333-8444-555555555555")!
        XCTAssertFalse(WorkoutRestAlarm.uniqueIDs([a, b]))
        XCTAssertTrue(WorkoutRestAlarm.hasOtherOwner(sessionID: a.id, activeSessions: [b]),
                      "Stopping an ended/deleted session must not cancel the colliding live session")
        XCTAssertFalse(WorkoutRestAlarm.hasOtherOwner(sessionID: a.id, activeSessions: [a]))
        b.id = UUID(); XCTAssertTrue(WorkoutRestAlarm.uniqueIDs([a, b]))
        XCTAssertFalse(WorkoutRestAlarm.hasOtherOwner(sessionID: a.id, activeSessions: [b]))
    }
    func testDismissalReceiptIsDeadlineSpecificAndHasNoMusicVolumeState() throws {
        let session = session()
        let receipt = WorkoutRestAlarmReceipt(sessionID: session.id, deadline: now.addingTimeInterval(120), volumeStep: 5)
        XCTAssertTrue(receipt.matches(sessionID: session.id, deadline: now.addingTimeInterval(120)))
        XCTAssertFalse(receipt.matches(sessionID: session.id, deadline: now.addingTimeInterval(121)))
        XCTAssertFalse(receipt.matches(sessionID: UUID(), deadline: receipt.deadline))
        XCTAssertTrue(receipt.isValid)
        XCTAssertEqual(try JSONDecoder().decode(WorkoutRestAlarmReceipt.self, from: JSONEncoder().encode(receipt)), receipt)
    }
    func testManualDismissalSurvivesAutosaveButExplicitRearmAndNewRestAreAllowed() {
        let id = UUID(), deadline = now.addingTimeInterval(120)
        let receipt = WorkoutRestAlarmReceipt(sessionID: id, deadline: deadline, volumeStep: 5)
        XCTAssertEqual(WorkoutRestAlarm.scheduling(sessionID: id, deadline: deadline, volumeStep: 5, receipt: receipt, exists: false, force: false), .dismissedOrUncertain)
        XCTAssertEqual(WorkoutRestAlarm.scheduling(sessionID: id, deadline: deadline, volumeStep: 10, receipt: receipt, exists: false, force: false), .dismissedOrUncertain)
        XCTAssertEqual(WorkoutRestAlarm.scheduling(sessionID: id, deadline: deadline, volumeStep: 5, receipt: receipt, exists: false, force: true), .replace)
        XCTAssertEqual(WorkoutRestAlarm.scheduling(sessionID: id, deadline: deadline.addingTimeInterval(60), volumeStep: 5, receipt: receipt, exists: false, force: false), .replace)
    }
    func testUnchangedScheduleDoesNotDuplicateAndOnlyFutureCueGainChangesReplace() {
        let id = UUID(), deadline = now.addingTimeInterval(120)
        let receipt = WorkoutRestAlarmReceipt(sessionID: id, deadline: deadline, volumeStep: 5)
        XCTAssertEqual(WorkoutRestAlarm.scheduling(sessionID: id, deadline: deadline, volumeStep: 5, receipt: receipt, exists: true, force: false), .keep)
        XCTAssertEqual(WorkoutRestAlarm.scheduling(sessionID: id, deadline: deadline, volumeStep: 10, receipt: receipt, exists: true, force: false), .replace)
    }
    func testVolumeOnlySelectsFiniteCueGainAndRejectsInvalidSettingsBackup() throws {
        XCTAssertEqual(enabled.gain, 0.25); XCTAssertEqual(enabled.soundName, "PivotRest-5.wav")
        var data = AppData(); data.settings.workoutRestAudio = .init(enabled: true, volumeStep: 20)
        XCTAssertEqual(try BackupCodec.decode(BackupCodec.encode(data)).settings.workoutRestAudio?.gain, 1)
        for step in [0, -1, 21, Int.max] {
            let invalid = WorkoutRestAudioSettings(enabled: true, volumeStep: step)
            XCTAssertFalse(invalid.isValid)
            XCTAssertEqual(WorkoutRestAlarm.decision(session: session(), settings: invalid, now: now), .cancel)
            data.settings.workoutRestAudio = invalid
            XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(data)))
        }
    }
}
