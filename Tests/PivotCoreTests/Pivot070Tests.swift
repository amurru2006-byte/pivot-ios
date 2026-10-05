import XCTest
@testable import PivotCore

final class Pivot070Tests: XCTestCase {
    func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    var now: Date { date("2026-10-05T12:00:00+02:00") }
    func event(_ title: String, _ kind: EventKind, _ hour: Int, _ end: Int) -> CalendarItem {
        let day = date("2026-10-05T00:00:00+02:00")
        return .init(id: title, eventIdentifier: title, calendarIdentifier: "test", calendarTitle: "Test", title: title,
                     start: day.addingTimeInterval(Double(hour) * 3600), end: day.addingTimeInterval(Double(end) * 3600), location: "", notes: "", colorHex: "00FF00", isAllDay: false, writable: true, kind: kind)
    }
    func workout(_ type: String = "strength", minutes: Int = 60, calories: Double? = 250) -> HealthWorkoutSummary {
        let start = date("2026-10-05T05:50:00+02:00")
        return .init(id: "watch", start: start, end: start.addingTimeInterval(Double(minutes) * 60), type: type, durationSeconds: minutes * 60, activeCalories: calories)
    }
    var gym: CalendarItem { event("palestra", .workout, 10, 12) }
    func draft() -> ActualWorkoutDraft {
        .init(source: gym, start: workout().start, end: workout().end, wake: date("2026-10-05T05:15:00+02:00"), bedtime: date("2026-10-04T22:30:00+02:00"), breakfastDone: false)
    }
    func testEarlyStrengthAsksBeforeCounting() {
        let data = AppData(), reviews = WorkoutContext.refreshed([workout()], events: [gym], data: AppData(), now: now)
        XCTAssertEqual(reviews.count, 1); XCTAssertEqual(reviews[0].eventIDs, [gym.id]); XCTAssertNil(data.records[gym.id])
    }
    func testNoONWorkoutNoQuestion() { XCTAssertTrue(WorkoutContext.refreshed([workout()], events: [], data: AppData(), now: now).isEmpty) }
    func testCommuteDoesNotCountEvenWithGymThatDay() {
        XCTAssertTrue(WorkoutContext.refreshed([workout("walk", minutes: 17, calories: 80)], events: [gym], data: AppData(), now: now).isEmpty)
        XCTAssertFalse(WorkoutContext.significantCardio(workout("walk", minutes: 17, calories: 80), settings: Settings()))
    }
    func testCardioMissingCaloriesIsNotAutomaticallySignificant() { XCTAssertFalse(WorkoutContext.significantCardio(workout("walk", minutes: 60, calories: nil), settings: Settings())) }
    func testLongCardioAsksAndDoesNotReplaceStrength() {
        let walk = event("cardio camminata", .workout, 18, 19)
        let reviews = WorkoutContext.refreshed([workout("walk")], events: [gym, walk], data: AppData(), now: now)
        XCTAssertEqual(reviews.first?.eventIDs, [walk.id])
    }
    func testDismissedReviewDoesNotReturnAfterRelaunch() throws {
        var data = AppData(); data.workoutReviews = [.init(workout: workout(), eventIDs: [gym.id], dismissed: true)]
        let restored = try BackupCodec.decode(BackupCodec.encode(data))
        let result = WorkoutContext.refreshed([workout()], events: [gym], data: restored, now: now)
        XCTAssertEqual(result.count, 1); XCTAssertTrue(result[0].dismissed)
    }
    func testAlreadyLinkedWorkoutNotOfferedTwice() {
        var data = AppData(); var record = EventRecord(id: gym.id, snapshot: gym); record.health = workout(); record.status = .completed; data.records[gym.id] = record
        XCTAssertTrue(WorkoutContext.refreshed([workout()], events: [gym], data: data, now: now).isEmpty)
    }
    func testParserExactExampleAnd24HourClock() {
        XCTAssertEqual(WorkoutContext.statedStart("Sono andato in pale alle 5.50 AM oggi", now: now), workout().start)
        XCTAssertEqual(WorkoutContext.statedStart("Ho iniziato palestra alle 05:50 oggi", now: now), workout().start)
    }
    func testParserDoesNotTakeWakeTimeAsGymTime() {
        XCTAssertEqual(WorkoutContext.statedStart("Mi sono svegliato alle 5:00 e sono andato in palestra alle 5:50 AM", now: now), workout().start)
    }
    func testParserDoesNotInventFactualFutureOrNegatedWorkouts() {
        XCTAssertNil(WorkoutContext.statedStart("Non sono andato in pale alle 5.50 AM", now: now))
        XCTAssertNil(WorkoutContext.statedStart("Domani sono andato in pale alle 5.50 AM", now: now))
        XCTAssertNil(WorkoutContext.statedStart("Sono andato in pale alle 5.50 PM oggi", now: now))
        XCTAssertNil(WorkoutContext.statedStart("Sono andato in pale alle 25.50 oggi", now: now))
    }
    func testActualEventMayBeEarlierThanQuietHours() { XCTAssertNil(WorkoutContext.validate(draft(), events: [gym], now: now)) }
    func testUnknownEndAndBreakfastMustBeAsked() {
        var value = draft(); value.end = nil; XCTAssertNotNil(WorkoutContext.validate(value, events: [gym], now: now))
        value = draft(); value.breakfastDone = nil; XCTAssertNotNil(WorkoutContext.validate(value, events: [gym], now: now))
    }
    func testWakeAfterGymRejected() {
        var value = draft(); value.wake = date("2026-10-05T08:00:00+02:00"); XCTAssertNotNil(WorkoutContext.validate(value, events: [gym], now: now))
    }
    func testMissingPreparationEndNotInvented() {
        let wake = event("sveglia", .routine, 8, 9)
        XCTAssertNotNil(WorkoutContext.validate(draft(), events: [gym, wake], now: now))
        var value = draft(); value.wakeEnd = value.start
        XCTAssertNil(WorkoutContext.validate(value, events: [gym, wake], now: now))
    }
    func testBreakfastOverlappingWorkoutRejected() {
        var value = draft(); value.breakfastDone = true; value.breakfastStart = workout().start; value.breakfastEnd = workout().end
        XCTAssertNotNil(WorkoutContext.validate(value, events: [gym], now: now))
    }
    func testExternalCalendarEditInvalidatesConfirmation() {
        var current = gym; current.notes = "Nuovi dettagli"
        XCTAssertNotNil(WorkoutContext.validate(draft(), events: [current], now: now))
        var value = draft(); let wake = event("sveglia", .routine, 8, 9); value.contextEvents = [wake]; value.wakeEnd = value.start
        var changed = wake; changed.start = changed.start.addingTimeInterval(60)
        XCTAssertNotNil(WorkoutContext.validate(value, events: [gym, changed], now: now))
    }
    func testConfirmationStoresOnlyActualKnownDataAndKeepsBreakfastPending() {
        let breakfast = event("colazione", .meal, 8, 9); var data = AppData(); let value = draft()
        WorkoutContext.applyLocally(value, events: [gym, breakfast], data: &data, synced: false, now: now)
        XCTAssertEqual(data.records[gym.id]?.status, .completed); XCTAssertNil(data.records[breakfast.id]); XCTAssertNil(data.checkIns[PivotDate.key(now)]?.sleep?.durationSeconds)
        XCTAssertFalse(data.moves[0].syncedToCalendar)
    }
    func testNoMutationOnIncompleteConfirmation() {
        var data = AppData(); var value = draft(); value.end = nil
        WorkoutContext.applyLocally(value, events: [gym], data: &data, synced: true, now: now)
        XCTAssertTrue(data.moves.isEmpty); XCTAssertTrue(data.records.isEmpty)
    }
    func testHealthReviewExcludedFromDefaultExports() {
        var data = AppData(); data.workoutReviews = [.init(workout: workout(), eventIDs: [gym.id])]; var value = draft(); value.health = workout(); data.actualWorkoutDraft = value
        XCTAssertNil(HealthImport.exportData(data).workoutReviews); XCTAssertNil(HealthImport.exportData(data).actualWorkoutDraft)
        data.settings.includeHealthInExports = true; XCTAssertNotNil(HealthImport.exportData(data).actualWorkoutDraft)
    }
    func testConfirmingUnchangedHealthSleepDoesNotRemovePrivacyFlag() {
        var data = AppData(); let value = draft(), key = PivotDate.key(now)
        var sleep = SleepRecord(); sleep.bedtime = value.bedtime; sleep.durationSeconds = 24_000; sleep.importedFromHealth = true
        var check = DayCheckIn(id: key); check.sleep = sleep; check.wakeTime = value.wake; check.healthWakeTime = value.wake; data.checkIns[key] = check
        WorkoutContext.applyLocally(value, events: [gym], data: &data, synced: false, now: now)
        XCTAssertEqual(data.checkIns[key]?.sleep?.importedFromHealth, true)
        XCTAssertNil(HealthImport.exportData(data).checkIns[key]?.sleep)
    }
    func testEveningQuestionOnlyForUnansweredCardio() {
        let walk = event("cardio camminata", .workout, 18, 19), evening = date("2026-10-05T22:00:00+02:00")
        XCTAssertTrue(WorkoutContext.missingCardio(events: [walk], data: AppData(), now: now).isEmpty)
        XCTAssertEqual(WorkoutContext.missingCardio(events: [walk], data: AppData(), now: evening).count, 1)
        var data = AppData(); var record = EventRecord(id: walk.id, snapshot: walk); record.status = .skipped; record.reason = "Imprevisto"; data.records[walk.id] = record
        XCTAssertTrue(WorkoutContext.missingCardio(events: [walk], data: data, now: evening).isEmpty)
    }
    func testEveningNotificationRoutesMissingCardioToCoach() {
        let walk = event("cardio camminata", .workout, 18, 19)
        let planned = NotificationPlan.requests(events: [walk], data: AppData(), now: now)
        let evening = planned.first { $0.id == "evening-2026-10-05" }
        XCTAssertEqual(evening?.destination, "coach")
        XCTAssertTrue(evening?.body.contains("cardio") == true)
        var data = AppData(); var record = EventRecord(id: walk.id, snapshot: walk); record.status = .completed; data.records[walk.id] = record
        XCTAssertEqual(NotificationPlan.requests(events: [walk], data: data, now: now).first { $0.id == "evening-2026-10-05" }?.destination, "diary")
    }
}
