import XCTest
@testable import PivotCore

final class TrainingDurationEstimateTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-14T12:00:00+02:00")!
    private var plan: TrainingPlan {
        .init(payload: .init(formatVersion: 1, name: "Test", days: [
            .init(id: "squat-day", name: "Squat", exercises: [
                .init(id: "squat", name: "Barbell Squat", sets: 1, reps: "4-6", restSeconds: 180, coachNotes: "")])]))
    }
    private func session(_ plan: TrainingPlan, minutes: Double, age: Int) -> TrainingSession {
        var value = TrainingLibrary().makeSession(plan: plan, day: plan.payload.days[0], eventID: nil,
            now: now.addingTimeInterval(-Double(age) * 86400))
        value.end = value.start.addingTimeInterval(minutes * 60)
        value.exercises[0].sets[0].kg = 50; value.exercises[0].sets[0].reps = 6; value.exercises[0].sets[0].done = true
        return value
    }
    private func estimate(_ plan: TrainingPlan, _ sessions: [TrainingSession], scheduled: Int = 120) -> TrainingDurationEstimate? {
        TrainingDurationEstimate.make(plan: plan, day: plan.payload.days[0], library: .init(plans: [plan], sessions: sessions),
                                      calendarMinutes: scheduled, now: now)
    }
    func testUserExampleUsesMedianSeventyFiveMinutes() throws {
        let plan = plan, samples = [session(plan, minutes: 60, age: 21), session(plan, minutes: 90, age: 14), session(plan, minutes: 75, age: 7)]
        let result = try XCTUnwrap(estimate(plan, samples))
        XCTAssertEqual(result.activityMinutes, 75); XCTAssertEqual(result.source, .historyMedian)
        XCTAssertEqual(result.sampleIDs.count, 3); XCTAssertEqual(result.observedMinimumMinutes, 60)
        XCTAssertEqual(result.observedMaximumMinutes, 90); XCTAssertTrue(result.provisional)
    }
    func testMedianResistsAnAccidentallyLongSessionAndRoundsUp() throws {
        let plan = plan
        let result = try XCTUnwrap(estimate(plan, [60.2, 75.2, 76.2, 300].enumerated().map { session(plan, minutes: $0.element, age: $0.offset + 1) }))
        XCTAssertEqual(result.activityMinutes, 76)
        XCTAssertEqual(result.observedMaximumMinutes, 300)
    }
    func testFewerThanThreeSamplesKeepCalendarDurationWithoutInventingConfidence() throws {
        let plan = plan
        for count in 0...2 {
            let value = try XCTUnwrap(estimate(plan, (0..<count).map { session(plan, minutes: 75, age: $0 + 1) }))
            XCTAssertEqual(value.activityMinutes, 120); XCTAssertEqual(value.source, .calendar)
            XCTAssertEqual(value.sampleIDs.count, count); XCTAssertTrue(value.provisional)
        }
    }
    func testOtherPlansDaysAndPhasesNeverMix() throws {
        let plan = plan, other = self.plan
        var wrongDay = session(plan, minutes: 5, age: 2); wrongDay.dayID = "bench-day"
        var wrongPhase = session(plan, minutes: 5, age: 3); wrongPhase.phase = .deload
        let valid = (4...6).map { session(plan, minutes: 75, age: $0) }
        let value = try XCTUnwrap(estimate(plan, valid + [wrongDay, wrongPhase, session(other, minutes: 5, age: 1)]))
        XCTAssertEqual(value.activityMinutes, 75); XCTAssertEqual(value.sampleIDs.count, 3)
    }
    func testChangedPrescriptionExcludesOldSamples() throws {
        var plan = plan
        let old = (1...3).map { session(plan, minutes: 75, age: $0) }
        plan.payload.days[0].exercises[0].restSeconds = 60
        XCTAssertEqual(estimate(plan, old)?.source, .calendar)
        plan.payload.days[0].exercises[0].restSeconds = 180
        plan.payload.days[0].exercises[0].reps = "8-10"
        XCTAssertEqual(estimate(plan, old)?.sampleIDs.count, 0)
    }
    func testIncompleteSkippedRunningFutureAndInvalidTimersAreExcluded() throws {
        let plan = plan
        var running = session(plan, minutes: 75, age: 1); running.end = nil
        var skipped = session(plan, minutes: 75, age: 2); skipped.exercises[0].sets[0].done = false; skipped.exercises[0].sets[0].skipped = true
        var prefilled = session(plan, minutes: 75, age: 3); prefilled.exercises[0].sets[0].done = false
        var zero = session(plan, minutes: 75, age: 4); zero.end = zero.start
        let value = try XCTUnwrap(estimate(plan, [running, skipped, prefilled, zero, session(plan, minutes: 75, age: -1), session(plan, minutes: 1500, age: 5)]))
        XCTAssertTrue(value.sampleIDs.isEmpty); XCTAssertEqual(value.source, .calendar)
    }
    func testOnlyEightRecentSamplesWithinOneHundredEightyDaysAreUsed() throws {
        let plan = plan
        let samples = (1...10).map { session(plan, minutes: Double(70 + $0), age: $0) }
        let result = try XCTUnwrap(estimate(plan, samples + [session(plan, minutes: 5, age: 181)]))
        XCTAssertEqual(result.sampleIDs.count, 8); XCTAssertEqual(result.activityMinutes, 75)
        XCTAssertFalse(result.provisional)
    }
    func testDuplicateIdentityDoesNotInflateSampleCount() {
        let plan = plan, one = session(plan, minutes: 75, age: 7)
        XCTAssertEqual(estimate(plan, [one, one, one])?.source, .calendar)
        XCTAssertEqual(estimate(plan, [one, one, one])?.sampleIDs.count, 1)
    }
    func testExplicitZerosAreAcceptedButUnconfirmedTravelOrPreparationIsNot() throws {
        var rule = EventRule(flexibility: .movable, minimumMinutes: 75)
        XCTAssertNil(CalendarTimeBudget.confirmed(activityMinutes: 75, rule: rule, preparationMinutes: 0))
        rule.travelConfirmed = true
        XCTAssertNil(CalendarTimeBudget.confirmed(activityMinutes: 75, rule: rule, preparationMinutes: nil))
        XCTAssertEqual(CalendarTimeBudget.confirmed(activityMinutes: 75, rule: rule, preparationMinutes: 0)?.occupiedMinutes, 75)
        rule.travelBeforeMinutes = 20; rule.travelAfterMinutes = 25
        let budget = try XCTUnwrap(CalendarTimeBudget.confirmed(activityMinutes: 75, rule: rule, preparationMinutes: 10, marginMinutes: 5))
        XCTAssertEqual(budget.occupiedMinutes, 135); XCTAssertEqual(budget.beforeMinutes, 30); XCTAssertEqual(budget.afterMinutes, 30)
    }
    func testInvalidBudgetsAndCalendarFallbackAreRejected() {
        var rule = EventRule(flexibility: .movable, minimumMinutes: 75, travelBeforeMinutes: -1, travelConfirmed: true)
        XCTAssertNil(CalendarTimeBudget.confirmed(activityMinutes: 75, rule: rule, preparationMinutes: 0))
        rule.travelBeforeMinutes = 1440
        XCTAssertNil(CalendarTimeBudget.confirmed(activityMinutes: 75, rule: rule, preparationMinutes: 0))
        XCTAssertNil(estimate(plan, [], scheduled: 0))
    }
    func testLegacyUnambiguousDayAndDifferentWeightsRemainUsable() throws {
        let plan = plan
        var samples = (1...3).map { session(plan, minutes: 75, age: $0) }
        samples[0].dayID = nil; samples[0].dayName = " SQUAT "
        samples[1].exercises[0].sets[0].kg = 60
        XCTAssertEqual(estimate(plan, samples)?.source, .historyMedian)
    }
    func testChangedFailureOrExtraSetsDoNotReuseDifferentTimedWorkload() {
        let plan = plan
        var samples = (1...3).map { session(plan, minutes: 75, age: $0) }
        samples[0].exercises[0].sets[0].toFailure = true
        XCTAssertEqual(estimate(plan, samples)?.source, .calendar)
        samples[0].exercises[0].sets[0].toFailure = nil
        samples[0].exercises[0].sets.append(.init(number: 2, kg: 50, reps: 6, done: true, isAdditional: true))
        XCTAssertEqual(estimate(plan, samples)?.source, .calendar)
    }
}
