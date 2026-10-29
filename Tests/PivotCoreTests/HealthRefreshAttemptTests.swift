import XCTest
@testable import PivotCore

final class HealthRefreshAttemptTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    private func attempt() throws -> HealthRefreshAttempt {
        try XCTUnwrap(HealthRefreshAttempt(startedAt: start))
    }

    private func report(at date: Date, workoutSamples: Int = 0) -> HealthRefreshReport {
        .init(readAt: date, workoutSamples: workoutSamples, sleepDays: 0, workoutsApplied: 0,
              sleepDaysApplied: 0, sleepEventsCompleted: 0, pendingDecisions: 0)
    }

    private func successfulState() -> HealthRefreshState {
        var state = HealthRefreshState()
        XCTAssertTrue(state.begin(at: start))
        XCTAssertTrue(state.finish(.succeeded, at: start.addingTimeInterval(2),
                                   report: report(at: start.addingTimeInterval(1), workoutSamples: 2)))
        return state
    }

    func testNewAttemptHasNoCompletionOrFailureEvidence() throws {
        let value = try attempt()
        XCTAssertEqual(value.startedAt, start)
        XCTAssertEqual(value.outcome, .inProgress)
        XCTAssertNil(value.finishedAt)
        XCTAssertNil(value.failureStage)
        XCTAssertNil(value.failureCause)
    }

    func testEmptyReadIsSuccessfulWithoutInferringDeniedAccess() throws {
        let report = HealthRefreshReport.make(workouts: [], sleeps: [:], before: AppData(),
                                              after: AppData(), readAt: start.addingTimeInterval(1))
        let value = try XCTUnwrap(try attempt().finishing(.succeeded, at: report.readAt))
        XCTAssertEqual(report.workoutSamples, 0)
        XCTAssertEqual(report.sleepDays, 0)
        XCTAssertEqual(value.outcome, .succeeded)
        XCTAssertNil(value.failureCause)
        XCTAssertEqual(value.message, "Lettura completata.")
    }

    func testSuccessThenQueryFailurePreservesReportAndOriginalReadDate() throws {
        var state = successfulState()
        let originalReport = try XCTUnwrap(state.lastReport)
        let laterStart = start.addingTimeInterval(60)
        XCTAssertTrue(state.begin(at: laterStart))
        XCTAssertEqual(state.lastReport, originalReport)
        XCTAssertTrue(state.finish(.failed, at: laterStart.addingTimeInterval(1),
                                   stage: .workouts, cause: .queryFailed))
        XCTAssertEqual(state.lastAttempt?.outcome, .failed)
        XCTAssertEqual(state.lastReport, originalReport)
        XCTAssertEqual(state.lastReport?.readAt, start.addingTimeInterval(1))
        XCTAssertNotEqual(state.lastReport?.readAt, state.lastAttempt?.finishedAt)
    }

    func testSuccessThenCancellationPreservesReport() throws {
        var state = successfulState()
        let originalReport = try XCTUnwrap(state.lastReport)
        XCTAssertTrue(state.begin(at: start.addingTimeInterval(60)))
        XCTAssertTrue(state.finish(.cancelled, at: start.addingTimeInterval(61)))
        XCTAssertEqual(state.lastAttempt?.outcome, .cancelled)
        XCTAssertEqual(state.lastReport, originalReport)
    }

    func testSuccessThenPersistenceFailurePreservesReport() throws {
        var state = successfulState()
        let originalReport = try XCTUnwrap(state.lastReport)
        XCTAssertTrue(state.begin(at: start.addingTimeInterval(60)))
        XCTAssertTrue(state.finish(.failed, at: start.addingTimeInterval(61),
                                   stage: .persistence, cause: .persistenceFailed))
        XCTAssertEqual(state.lastAttempt?.outcome, .failed)
        XCTAssertEqual(state.lastAttempt?.failureCause, .persistenceFailed)
        XCTAssertEqual(state.lastReport, originalReport)
    }

    func testSuccessThenDeferralPreservesReport() throws {
        var state = successfulState()
        let originalReport = try XCTUnwrap(state.lastReport)
        XCTAssertTrue(state.begin(at: start.addingTimeInterval(60)))
        XCTAssertTrue(state.finish(.deferred, at: start.addingTimeInterval(61),
                                   stage: .reconciliation, cause: .changed))
        XCTAssertEqual(state.lastAttempt?.outcome, .deferred)
        XCTAssertEqual(state.lastReport, originalReport)
    }

    func testPartialReadReplacesBaseReportWithoutClaimingCompleteSuccess() throws {
        var state = successfulState()
        let originalReport = try XCTUnwrap(state.lastReport)
        let partialReport = report(at: start.addingTimeInterval(61), workoutSamples: 3)
        XCTAssertTrue(state.begin(at: start.addingTimeInterval(60)))
        XCTAssertTrue(state.finish(.partial, at: start.addingTimeInterval(62), stage: .heartRate,
                                   cause: .deferredDetails, report: partialReport))
        XCTAssertEqual(state.lastAttempt?.outcome, .partial)
        XCTAssertEqual(state.lastAttempt?.failureCause, .deferredDetails)
        XCTAssertNotEqual(state.lastAttempt?.outcome, .succeeded)
        XCTAssertEqual(state.lastReport, partialReport)
        XCTAssertNotEqual(state.lastReport, originalReport)
    }

    func testSuccessfulAndPartialStatesRequireAReportWithinTheirAttempt() {
        let outcomes: [HealthRefreshAttempt.Outcome] = [.succeeded, .partial]
        let end = start.addingTimeInterval(2)
        let invalidReadDates = [start.addingTimeInterval(-1), end.addingTimeInterval(1),
                                Date(timeIntervalSinceReferenceDate: .nan),
                                Date(timeIntervalSinceReferenceDate: .infinity),
                                Date(timeIntervalSinceReferenceDate: -.infinity)]
        for outcome in outcomes {
            var state = HealthRefreshState()
            XCTAssertTrue(state.begin(at: start))
            let before = state
            XCTAssertFalse(state.finish(outcome, at: end))
            XCTAssertEqual(state, before)
            for readAt in invalidReadDates {
                XCTAssertFalse(state.finish(outcome, at: end, report: report(at: readAt)))
                XCTAssertEqual(state, before)
            }
            XCTAssertTrue(state.finish(outcome, at: end, report: report(at: start)))
            XCTAssertEqual(state.lastAttempt?.outcome, outcome)
        }
    }

    func testFailureCancellationAndDeferralRejectUnexpectedReportAtomically() {
        let outcomes: [HealthRefreshAttempt.Outcome] = [.failed, .cancelled, .deferred]
        for outcome in outcomes {
            var state = successfulState()
            XCTAssertTrue(state.begin(at: start.addingTimeInterval(60)))
            let before = state
            XCTAssertFalse(state.finish(outcome, at: start.addingTimeInterval(62),
                                        report: report(at: start.addingTimeInterval(61))))
            XCTAssertEqual(state, before)
            XCTAssertTrue(state.finish(outcome, at: start.addingTimeInterval(62)))
            XCTAssertEqual(state.lastAttempt?.outcome, outcome)
            XCTAssertEqual(state.lastReport, before.lastReport)
        }
    }

    func testBeginRejectsOverlapAndInvalidDateWithoutChangingState() {
        var state = successfulState()
        let before = state
        XCTAssertFalse(state.begin(at: Date(timeIntervalSinceReferenceDate: .nan)))
        XCTAssertEqual(state, before)
        XCTAssertTrue(state.begin(at: start.addingTimeInterval(60)))
        let running = state
        XCTAssertFalse(state.begin(at: start.addingTimeInterval(61)))
        XCTAssertEqual(state, running)
        XCTAssertEqual(state.lastReport, before.lastReport)
    }

    func testFinishWithoutAttemptOrAfterCompletionCannotCreateOrReplaceReport() {
        var empty = HealthRefreshState()
        XCTAssertFalse(empty.finish(.succeeded, at: start, report: report(at: start)))
        XCTAssertEqual(empty, HealthRefreshState())
        var completed = successfulState()
        let before = completed
        XCTAssertFalse(completed.finish(.failed, at: start.addingTimeInterval(3)))
        XCTAssertFalse(completed.finish(.succeeded, at: start.addingTimeInterval(3),
                                        report: report(at: start.addingTimeInterval(3))))
        XCTAssertEqual(completed, before)
    }

    func testRejectedFinishKeepsAttemptOpenAndReportUnchanged() {
        var state = successfulState()
        let laterStart = start.addingTimeInterval(60)
        XCTAssertTrue(state.begin(at: laterStart))
        let before = state
        XCTAssertFalse(state.finish(.inProgress, at: laterStart))
        XCTAssertFalse(state.finish(.succeeded, at: laterStart.addingTimeInterval(-1),
                                    report: report(at: laterStart)))
        XCTAssertFalse(state.finish(.succeeded, at: laterStart, stage: .workouts,
                                    report: report(at: laterStart)))
        XCTAssertEqual(state, before)
        XCTAssertTrue(state.finish(.succeeded, at: laterStart, report: report(at: laterStart)))
        XCTAssertEqual(state.lastReport?.readAt, laterStart)
    }

    func testDeferredHeartRateDetailsRemainPartial() throws {
        let value = try XCTUnwrap(try attempt().finishing(.partial, at: start.addingTimeInterval(1),
                                                       stage: .heartRate, cause: .deferredDetails))
        XCTAssertEqual(value.outcome, .partial)
        XCTAssertNotEqual(value.outcome, .succeeded)
        XCTAssertEqual(value.failureStage, .heartRate)
        XCTAssertEqual(value.failureCause, .deferredDetails)
        XCTAssertEqual(value.message, "Lettura parziale: dettagli cardiaci non aggiornati.")
    }

    func testFailedHeartRateQueryIsDistinguishedFromDeferredDetails() throws {
        let failed = try XCTUnwrap(try attempt().finishing(.partial, at: start,
                                                        stage: .heartRate, cause: .queryFailed))
        let deferred = try XCTUnwrap(try attempt().finishing(.partial, at: start,
                                                          stage: .heartRate, cause: .deferredDetails))
        XCTAssertNotEqual(failed, deferred)
        XCTAssertEqual(failed.outcome, .partial)
        XCTAssertEqual(deferred.outcome, .partial)
    }

    func testAuthorizationErrorDoesNotClaimReadPermissionWasDenied() throws {
        let value = try XCTUnwrap(try attempt().finishing(.failed, at: start,
                                                       stage: .authorization, cause: .authorizationFailed))
        XCTAssertEqual(value.outcome, .failed)
        XCTAssertEqual(value.failureCause, .authorizationFailed)
        XCTAssertEqual(value.message, "Non è stato possibile completare l’accesso a Salute.")
    }

    func testUnavailableHealthHasItsOwnFailureStage() throws {
        let value = try XCTUnwrap(try attempt().finishing(.failed, at: start,
                                                       stage: .availability, cause: .unavailable))
        XCTAssertEqual(value.failureStage, .availability)
        XCTAssertEqual(value.message, "Salute non è disponibile.")
    }

    func testFailedLocalSaveIsNotSuccessfulReadingApplication() throws {
        let value = try XCTUnwrap(try attempt().finishing(.failed, at: start,
                                                       stage: .persistence, cause: .persistenceFailed))
        XCTAssertEqual(value.outcome, .failed)
        XCTAssertEqual(value.failureCause, .persistenceFailed)
        XCTAssertEqual(value.message, "Aggiornamento locale non salvato.")
    }

    func testCancelledReadIsTerminalWithoutFailureOrSuccess() throws {
        let value = try XCTUnwrap(try attempt().finishing(.cancelled, at: start.addingTimeInterval(1)))
        XCTAssertEqual(value.outcome, .cancelled)
        XCTAssertNil(value.failureStage)
        XCTAssertNil(value.failureCause)
        XCTAssertNil(value.finishing(.succeeded, at: start.addingTimeInterval(2)))
    }

    func testChangedContextCanDeferWithoutClaimingFailureOrSuccess() throws {
        let value = try XCTUnwrap(try attempt().finishing(.deferred, at: start,
                                                       stage: .reconciliation, cause: .changed))
        XCTAssertEqual(value.outcome, .deferred)
        XCTAssertEqual(value.failureStage, .reconciliation)
        XCTAssertEqual(value.message, "Aggiornamento rimandato: il contesto è cambiato.")
    }

    func testFailureDetailsAreOptionalAndNotInvented() throws {
        let outcomes: [HealthRefreshAttempt.Outcome] = [.partial, .failed, .deferred]
        for outcome in outcomes {
            let value = try XCTUnwrap(try attempt().finishing(outcome, at: start))
            XCTAssertEqual(value.outcome, outcome)
            XCTAssertNil(value.failureStage)
            XCTAssertNil(value.failureCause)
            XCTAssertFalse(value.message.isEmpty)
        }
    }

    func testSuccessfulAndCancelledOutcomesRejectFailureDetails() throws {
        let outcomes: [HealthRefreshAttempt.Outcome] = [.succeeded, .cancelled]
        for outcome in outcomes {
            XCTAssertNil(try attempt().finishing(outcome, at: start, stage: .workouts))
            XCTAssertNil(try attempt().finishing(outcome, at: start, cause: .queryFailed))
        }
    }

    func testEveryTerminalOutcomeKeepsStartAndCannotBeReplaced() throws {
        let end = start.addingTimeInterval(5)
        let outcomes: [HealthRefreshAttempt.Outcome] = [.succeeded, .partial, .failed, .cancelled, .deferred]
        for outcome in outcomes {
            let value = try XCTUnwrap(try attempt().finishing(outcome, at: end))
            XCTAssertEqual(value.startedAt, start)
            XCTAssertEqual(value.finishedAt, end)
            XCTAssertNil(value.finishing(.failed, at: end.addingTimeInterval(1)))
        }
    }

    func testInvalidStartDateIsRejected() {
        for interval in [Double.nan, .infinity, -.infinity] {
            XCTAssertNil(HealthRefreshAttempt(startedAt: Date(timeIntervalSinceReferenceDate: interval)))
        }
    }

    func testFinishRejectsInvalidOrReversedDatesAndInProgressOutcome() throws {
        let value = try attempt()
        XCTAssertNil(value.finishing(.succeeded, at: start.addingTimeInterval(-1)))
        for interval in [Double.nan, .infinity, -.infinity] {
            XCTAssertNil(value.finishing(.succeeded, at: Date(timeIntervalSinceReferenceDate: interval)))
        }
        XCTAssertNil(value.finishing(.inProgress, at: start))
        XCTAssertEqual(try XCTUnwrap(value.finishing(.succeeded, at: start)).finishedAt, start)
    }
}
