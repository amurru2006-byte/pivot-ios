import XCTest
@testable import PivotCore

final class TrainingDurationPredictionTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-18T12:00:00+02:00")!
    private var plan: TrainingPlan {
        .init(payload: .init(formatVersion: 1, name: "Programma QA", days: [.init(id: "day-qa", name: "Giorno QA", exercises: [
            .init(id: "exercise-qa", name: "Movimento QA", sets: 1, reps: "6", restSeconds: 60, coachNotes: "")])]))
    }
    private func sample(_ plan: TrainingPlan, minutes: Double, age: Int, hour: Int = 9) -> TrainingSession {
        let date = PivotDate.calendar.date(byAdding: .day, value: -age, to: now)!
        let start = PivotDate.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date)!
        var value = TrainingLibrary().makeSession(plan: plan, day: plan.payload.days[0], eventID: nil, now: start)
        value.end = start.addingTimeInterval(minutes * 60)
        value.exercises[0].sets[0].kg = 50; value.exercises[0].sets[0].reps = 6; value.exercises[0].sets[0].done = true
        return value
    }
    private func estimate(_ plan: TrainingPlan, sessions: [TrainingSession], start: Date? = nil, scheduled: Int? = nil) -> TrainingDurationEstimate? {
        TrainingDurationEstimate.make(plan: plan, day: plan.payload.days[0], library: .init(plans: [plan], sessions: sessions),
                                      calendarMinutes: scheduled, now: now, scheduledStart: start)
    }
    private func prediction(_ plan: TrainingPlan, session: TrainingSession) throws -> TrainingDurationPrediction {
        let result = try XCTUnwrap(estimate(plan, sessions: [60, 75, 90].enumerated().map { sample(plan, minutes: Double($0.element), age: $0.offset + 1) }))
        return try XCTUnwrap(TrainingDurationPrediction.capture(result, session: session, now: session.start))
    }
    func testDescriptiveQuartilesAreNotMinMaxOrAConfidenceProbability() throws {
        let stats = try XCTUnwrap(DurationStatistics.make([60, 75, 90, 75, 80]))
        XCTAssertEqual(stats.medianMinutes, 75); XCTAssertEqual(stats.lowerMinutes, 75); XCTAssertEqual(stats.upperMinutes, 80)
        XCTAssertEqual(stats.minimumMinutes, 60); XCTAssertEqual(stats.maximumMinutes, 90)
    }
    func testQuartilesRoundOutwardsAndMedianUpwards() throws {
        let stats = try XCTUnwrap(DurationStatistics.make([60.2, 75.2, 80.2, 90.2]))
        XCTAssertEqual(stats.medianMinutes, 78); XCTAssertEqual(stats.lowerMinutes, 71); XCTAssertEqual(stats.upperMinutes, 83)
    }
    func testStatisticsRejectInvalidAndSparseInputs() {
        for values in [[], [60], [60, 70], [60, 70, .nan], [60, 70, .infinity], [60, 70, 0], [60, 70, -1], [60, 70, 1441]] as [[Double]] {
            XCTAssertNil(DurationStatistics.make(values))
        }
    }
    func testHistoryCanEstimateWithoutInventingACalendarDuration() {
        let plan = self.plan
        XCTAssertNil(estimate(plan, sessions: []))
        XCTAssertNil(estimate(plan, sessions: [sample(plan, minutes: 75, age: 1)]))
        let value = estimate(plan, sessions: (1...3).map { sample(plan, minutes: 75, age: $0) })
        XCTAssertEqual(value?.activityMinutes, 75); XCTAssertEqual(value?.source, .historyMedian)
    }
    func testSparseCalendarFallbackHasNoInventedObservedBand() {
        let plan = self.plan
        let value = estimate(plan, sessions: [sample(plan, minutes: 75, age: 1)], scheduled: 100)
        XCTAssertEqual(value?.source, .calendar); XCTAssertNil(value?.statistics)
        XCTAssertEqual(value?.schedulingMinutes, 100)
    }
    func testSessionEstimateUsesDeclaredPhaseWithoutEditingPlan() {
        var plan = self.plan
        plan.payload.phase = .loading
        let original = plan
        let sessions = (1...3).map { sample(plan, minutes: 75, age: $0) }
        var next = TrainingLibrary().makeSession(plan: plan, day: plan.payload.days[0], eventID: nil, now: now)
        let library = TrainingLibrary(plans: [plan], sessions: sessions)
        XCTAssertEqual(TrainingDurationEstimate.make(session: next, library: library, calendarMinutes: nil, now: now)?.activityMinutes, 75)
        next.phase = nil
        XCTAssertNil(TrainingDurationEstimate.make(session: next, library: library, calendarMinutes: nil, now: now))
        XCTAssertEqual(library.plans[0], original)
    }
    func testSessionEstimateRejectsMissingPlanChangedWorkloadAndAmbiguousLegacyDay() {
        let plan = self.plan
        var next = TrainingLibrary().makeSession(plan: plan, day: plan.payload.days[0], eventID: nil, now: now)
        XCTAssertNil(TrainingDurationEstimate.make(session: next, library: .init(), calendarMinutes: 80, now: now))
        next.exercises[0].exercise.sets += 1
        XCTAssertNil(TrainingDurationEstimate.make(session: next, library: .init(plans: [plan]), calendarMinutes: 80, now: now))
        var duplicate = plan
        var day = duplicate.payload.days[0]; day.id = "day-duplicate"
        duplicate.payload.days.append(day)
        next = TrainingLibrary().makeSession(plan: plan, day: plan.payload.days[0], eventID: nil, now: now)
        next.dayID = nil
        XCTAssertNil(TrainingDurationEstimate.make(session: next, library: .init(plans: [duplicate]), calendarMinutes: 80, now: now))
    }
    func testFiveComparableEveningsCanUseTimeContextWithoutMixingWorkloads() {
        let plan = self.plan
        let morning = (1...5).map { sample(plan, minutes: 60, age: $0, hour: 9) }
        let evening = (6...10).map { sample(plan, minutes: 90, age: $0, hour: 20) }
        let start = PivotDate.calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now)!
        let value = estimate(plan, sessions: morning + evening, start: start)
        XCTAssertEqual(value?.activityMinutes, 90); XCTAssertEqual(value?.timeBand, .evening)
        XCTAssertEqual(value?.sampleIDs.count, 5)
    }
    func testSparseContextFallsBackToComparableHistoryNotASingleEvening() {
        let plan = self.plan
        let samples = (1...5).map { sample(plan, minutes: 60, age: $0) } + [sample(plan, minutes: 120, age: 6, hour: 20)]
        let value = estimate(plan, sessions: samples, start: now.addingTimeInterval(8 * 3600))
        XCTAssertEqual(value?.activityMinutes, 60); XCTAssertNil(value?.timeBand)
    }
    func testPastTargetCannotUseFutureObservationsForAHistoricalPrediction() {
        let plan = self.plan
        XCTAssertNil(estimate(plan, sessions: (1...5).map { sample(plan, minutes: 75, age: $0) }, start: now.addingTimeInterval(-86400)))
    }
    func testUserExcludedSessionDoesNotAlterTheRestOfHistory() {
        let plan = self.plan
        var samples = (1...3).map { sample(plan, minutes: 75, age: $0) }
        samples[0].durationExcluded = true
        XCTAssertNil(estimate(plan, sessions: samples)); XCTAssertEqual(samples.count, 3)
        samples[0].durationExcluded = false
        XCTAssertEqual(estimate(plan, sessions: samples)?.activityMinutes, 75)
    }
    func testSchedulingUsesUpperObservedQuartileOnlyWithEnoughSamples() {
        let plan = self.plan
        let few = estimate(plan, sessions: [60, 75, 300].enumerated().map { sample(plan, minutes: Double($0.element), age: $0.offset + 1) })
        XCTAssertEqual(few?.schedulingMinutes, 75)
        let many = estimate(plan, sessions: [60, 70, 75, 85, 300].enumerated().map { sample(plan, minutes: Double($0.element), age: $0.offset + 1) })
        XCTAssertEqual(many?.schedulingMinutes, 85)
    }
    func testPredictionIsCapturedBeforeCompletionAndNeverBackfilled() throws {
        let plan = self.plan
        var session = TrainingLibrary().makeSession(plan: plan, day: plan.payload.days[0], eventID: nil, now: now)
        let estimate = try XCTUnwrap(self.estimate(plan, sessions: [], scheduled: 80))
        XCTAssertNotNil(TrainingDurationPrediction.capture(estimate, session: session, now: now))
        XCTAssertNil(TrainingDurationPrediction.capture(estimate, session: session, now: now.addingTimeInterval(61)))
        session.end = now.addingTimeInterval(3600)
        XCTAssertNil(TrainingDurationPrediction.capture(estimate, session: session, now: now))
    }
    func testActualFeedbackMeasuresRealErrorAndDoesNotInflateDuplicateSamples() throws {
        let plan = self.plan
        var active = TrainingLibrary().makeSession(plan: plan, day: plan.payload.days[0], eventID: nil, now: now)
        active.durationPrediction = try prediction(plan, session: active)
        active.exercises[0].sets[0].kg = 50; active.exercises[0].sets[0].reps = 6; active.exercises[0].sets[0].done = true
        active.end = now.addingTimeInterval(80 * 60)
        let quality = TrainingPredictionQuality.make([active, active])
        XCTAssertEqual(quality.evaluatedCount, 1); XCTAssertEqual(quality.meanAbsoluteErrorMinutes, 5)
        XCTAssertEqual(quality.bandCount, 1); XCTAssertEqual(quality.withinObservedBandCount, 1)
    }
    func testUnfinishedChangedOrExcludedWorkoutsDoNotPretendPredictionErrors() throws {
        let plan = self.plan
        var value = TrainingLibrary().makeSession(plan: plan, day: plan.payload.days[0], eventID: nil, now: now)
        value.durationPrediction = try prediction(plan, session: value)
        XCTAssertNil(value.durationPrediction?.actualMinutes(for: value))
        value.end = now.addingTimeInterval(3600)
        XCTAssertNil(value.durationPrediction?.actualMinutes(for: value))
        value.exercises[0].sets[0].kg = 50; value.exercises[0].sets[0].reps = 6; value.exercises[0].sets[0].done = true
        XCTAssertNotNil(value.durationPrediction?.actualMinutes(for: value))
        value.durationExcluded = true; XCTAssertNil(value.durationPrediction?.actualMinutes(for: value))
        value.durationExcluded = nil; value.start = now.addingTimeInterval(60)
        XCTAssertNil(value.durationPrediction?.actualMinutes(for: value))
        value.start = now; value.exercises[0].sets[0].restSeconds = 180
        XCTAssertNil(value.durationPrediction?.actualMinutes(for: value))
    }
    func testLegacyWorkoutsDoNotAcquireInventedPredictionQuality() {
        let value = sample(plan, minutes: 75, age: 1)
        let quality = TrainingPredictionQuality.make([value])
        XCTAssertEqual(quality.evaluatedCount, 0); XCTAssertNil(quality.meanAbsoluteErrorMinutes)
    }
    func testPredictionRoundTripAndExclusionSurviveBackup() throws {
        let plan = self.plan
        var session = TrainingLibrary().makeSession(plan: plan, day: plan.payload.days[0], eventID: nil, now: now)
        session.durationPrediction = try prediction(plan, session: session); session.durationExcluded = true
        var data = AppData(); data.training = .init(plans: [plan], sessions: [session])
        let restored = try BackupCodec.decode(BackupCodec.encodeCompact(data))
        XCTAssertEqual(restored.training?.sessions[0].durationPrediction, session.durationPrediction)
        XCTAssertEqual(restored.training?.sessions[0].durationExcluded, true)
    }
    func testInvalidSelfReferencingPredictionIsRejectedWithoutChangingSession() throws {
        let plan = self.plan
        var session = TrainingLibrary().makeSession(plan: plan, day: plan.payload.days[0], eventID: nil, now: now)
        session.durationPrediction = try prediction(plan, session: session)
        session.durationPrediction?.sampleIDs = [session.id]
        XCTAssertNil(session.durationPrediction?.actualMinutes(for: session))
        XCTAssertThrowsError(try TrainingLibrary(plans: [plan], sessions: [session]).validate())
    }
    func testInvalidIntervalAndNonfinitePredictionDatesAreRejected() throws {
        let plan = self.plan
        let session = TrainingLibrary().makeSession(plan: plan, day: plan.payload.days[0], eventID: nil, now: now)
        var prediction = try self.prediction(plan, session: session)
        prediction.lowerMinutes = 90; XCTAssertFalse(prediction.isValid)
        prediction.lowerMinutes = 60; prediction.upperMinutes = 70; XCTAssertFalse(prediction.isValid)
        prediction.upperMinutes = 90; prediction.capturedAt = Date(timeIntervalSinceReferenceDate: .infinity)
        XCTAssertFalse(prediction.isValid)
    }
    func testLocalPredictionDetailsAreNotAddedToCloudRequest() throws {
        let plan = self.plan
        var session = TrainingLibrary().makeSession(plan: plan, day: plan.payload.days[0], eventID: nil, now: now)
        session.durationPrediction = try prediction(plan, session: session)
        var data = AppData(); data.training = .init(plans: [plan], sessions: [session])
        let snapshot = try CoachV8Snapshot.make(message: "Organizza la giornata", events: [], data: data, now: now, purpose: "conversation")
        let sent = String(decoding: snapshot.encodedRequest, as: UTF8.self)
        XCTAssertFalse(sent.contains("expectedMinutes")); XCTAssertFalse(sent.contains("sampleIDs"))
        XCTAssertFalse(sent.contains(plan.id.uuidString)); XCTAssertFalse(sent.contains("exercise-qa"))
    }
}
