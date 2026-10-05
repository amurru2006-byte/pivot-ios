import XCTest
@testable import PivotCore

final class Pivot060Tests: XCTestCase {
    func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    func event(_ id: String, _ kind: EventKind, _ from: Int, _ to: Int, location: String = "") -> CalendarItem {
        let day = date("2026-10-05T00:00:00+02:00")
        return CalendarItem(id: id, eventIdentifier: id, calendarIdentifier: id, calendarTitle: "Test", title: id,
                            start: day.addingTimeInterval(Double(from) * 3600), end: day.addingTimeInterval(Double(to) * 3600),
                            location: location, notes: "", colorHex: "#D02D68", isAllDay: false, writable: true, kind: kind)
    }
    func testLunchInsideFriendsOutingIsNotAConflict() {
        let friends = event("amici", .friends, 10, 18, location: "Milano"), lunch = event("pranzo", .meal, 13, 14, location: "Casa")
        XCTAssertEqual(EventContext.relation(friends, lunch, data: AppData()).0, .included)
        XCTAssertTrue(Planner.overlaps(on: lunch.start, events: [friends, lunch], data: AppData()).isEmpty)
        XCTAssertTrue(EventContext.decisions(on: lunch.start, events: [friends, lunch], data: AppData()).isEmpty)
    }
    func testSeparateRestaurantMealNeedsConfirmation() {
        let outing = event("des", .partner, 10, 18, location: "Pavia"), lunch = event("pranzo", .meal, 13, 14, location: "Ristorante Milano")
        XCTAssertEqual(EventContext.relation(outing, lunch, data: AppData()).0, .uncertain)
    }
    func testPartlyOverlappingMealIsNotSilentlyIncluded() {
        XCTAssertNotEqual(EventContext.relation(event("amici", .friends, 13, 18), event("pranzo", .meal, 12, 14), data: AppData()).0, .included)
    }
    func testLectureAndGymAreIncompatibleEvenAtSameLocation() {
        XCTAssertEqual(EventContext.relation(event("lezione", .university, 10, 12), event("palestra", .workout, 11, 13), data: AppData()).0, .conflict)
    }
    func testDentistAndShoppingAreDedicatedAppointments() {
        XCTAssertEqual(EventContext.relation(event("dentista", .other, 10, 12), event("spesa", .other, 11, 13), data: AppData()).0, .conflict)
    }
    func testTravelDuringOutingNeedsOneQuestion() {
        XCTAssertEqual(EventContext.relation(event("amici", .friends, 10, 18), event("train to Milano", .other, 12, 13), data: AppData()).0, .uncertain)
    }
    func testUserAnswerInvalidatesWhenCalendarChanges() {
        let a = event("uscita", .friends, 10, 18), b = event("viaggio", .other, 12, 13)
        var data = AppData(); data.contextAnswers = [.init(id: EventContext.key(a, b), compatible: true, answeredAt: a.start)]
        XCTAssertEqual(EventContext.relation(a, b, data: data).0, .included)
        var changed = b; changed.location = "Altro luogo"
        XCTAssertEqual(EventContext.relation(a, changed, data: data).0, .uncertain)
    }
    func testDifferentPlacesNeedTravelTimeButSamePlacesDoNot() {
        let a = event("dentista", .other, 10, 11, location: "Milano"), b = event("spesa", .other, 11, 12, location: "Trezzo")
        XCTAssertEqual(EventContext.decisions(on: a.start, events: [a, b], data: AppData()).first?.relation, .uncertain)
        var same = b; same.location = a.location
        XCTAssertTrue(EventContext.decisions(on: a.start, events: [a, same], data: AppData()).isEmpty)
    }
    func testConfirmedTravelIsComparedToGap() {
        let a = event("dentista", .other, 10, 11, location: "Milano"), b = event("spesa", .other, 12, 13, location: "Trezzo")
        var data = AppData(); data.contextAnswers = [.init(id: EventContext.key(a, b), compatible: false, answeredAt: a.start, travelMinutes: 75)]
        XCTAssertEqual(EventContext.decisions(on: a.start, events: [a, b], data: data).first?.relation, .travel)
        data.contextAnswers?[0].travelMinutes = 40
        XCTAssertTrue(EventContext.decisions(on: a.start, events: [a, b], data: data).isEmpty)
    }
    func testCompletedAndSkippedEventsDoNotCreateNewQuestions() {
        let a = event("lezione", .university, 10, 12), b = event("palestra", .workout, 10, 12)
        var data = AppData(); var record = EventRecord(id: a.id, snapshot: a); record.status = .completed; data.records[a.id] = record
        XCTAssertTrue(EventContext.decisions(on: a.start, events: [a, b], data: data).isEmpty)
    }
    func testPriorityChoosesDedicatedEventOverOuting() {
        let a = event("amici", .friends, 10, 18), b = event("esame", .exam, 12, 14)
        XCTAssertEqual(Planner.preferredEvent([a, b], data: AppData(), now: b.start)?.id, b.id)
    }
    func testDeferredQuestionSurvivesRoundTrip() throws {
        let a = event("amici", .friends, 10, 18), b = event("viaggio", .other, 12, 13)
        var data = AppData(); data.decisions = EventContext.refreshed(events: [a, b], data: data, now: a.start); data.decisions?[0].deferred = true
        let restored = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertTrue(EventContext.refreshed(events: [a, b], data: restored, now: a.start)[0].deferred)
    }
    func testSleepDeduplicatesSourcesAndUsesActualDayAfterMidnight() {
        let start = date("2026-10-05T01:00:00+02:00"), end = date("2026-10-05T08:00:00+02:00")
        let value = HealthImport.sleep(asleep: [.init(start: start, end: end), .init(start: start.addingTimeInterval(3600), end: end)], awake: [], endingOn: end)
        XCTAssertEqual(value?.durationSeconds, 7 * 3600)
        XCTAssertEqual(value?.start, start)
        XCTAssertNil(value?.awakenings)
        XCTAssertNil(HealthImport.sleep(asleep: [], awake: [], endingOn: end))
    }
    func testMainSleepDoesNotAddSeparateNap() {
        let a = date("2026-10-05T01:00:00+02:00"), b = date("2026-10-05T08:00:00+02:00")
        let nap = date("2026-10-05T15:00:00+02:00")
        XCTAssertEqual(HealthImport.sleep(asleep: [.init(start: a, end: b), .init(start: nap, end: nap.addingTimeInterval(3600))], awake: [], endingOn: b)?.durationSeconds, 7 * 3600)
    }
    func testSleepRespectsDSTAndAwakeIntervals() {
        let a = date("2026-10-25T01:30:00+02:00"), b = date("2026-10-25T03:30:00+01:00")
        XCTAssertEqual(HealthImport.sleep(asleep: [.init(start: a, end: b)], awake: [], endingOn: b)?.durationSeconds, 3 * 3600)
    }
    func testWalkingCommuteDoesNotCompleteScheduledWorkout() {
        let gym = event("palestra", .workout, 10, 13), walk = event("camminata", .workout, 16, 17)
        let summary = HealthWorkoutSummary(id: "hk", start: gym.start, end: gym.start.addingTimeInterval(1200), type: "walk", durationSeconds: 1200)
        XCTAssertTrue(HealthImport.candidates(summary, events: [gym, walk]).isEmpty)
    }
    func testOnlyUniqueTypeAndTimeWorkoutCanBeImported() {
        let walk = event("camminata", .workout, 10, 11)
        let summary = HealthWorkoutSummary(id: "hk", start: walk.start, end: walk.end, type: "walk", durationSeconds: 3600, distanceKM: 4, activeCalories: 210)
        XCTAssertEqual(HealthImport.candidates(summary, events: [walk]).map(\.id), [walk.id])
        var data = AppData(); HealthImport.apply(summary, to: walk, data: &data)
        XCTAssertEqual(data.records[walk.id]?.status, .completed)
        XCTAssertEqual(data.records[walk.id]?.cardio?.distanceKM, 4)
        HealthImport.apply(summary, to: walk, data: &data)
        XCTAssertEqual(data.records.count, 1)
    }
    func testManualOutcomeIsNeverOverwrittenByHealth() {
        let walk = event("camminata", .workout, 10, 11)
        let summary = HealthWorkoutSummary(id: "hk", start: walk.start, end: walk.end, type: "walk", durationSeconds: 3600)
        var data = AppData(); var record = EventRecord(id: walk.id, snapshot: walk); record.status = .skipped; data.records[walk.id] = record
        HealthImport.apply(summary, to: walk, data: &data)
        XCTAssertEqual(data.records[walk.id]?.status, .skipped); XCTAssertNil(data.records[walk.id]?.health)
    }
    func testHealthExportsRequireExplicitConsent() {
        let walk = event("camminata", .workout, 10, 11)
        let summary = HealthWorkoutSummary(id: "hk", start: walk.start, end: walk.end, type: "walk", durationSeconds: 3600)
        var data = AppData(); HealthImport.apply(summary, to: walk, data: &data)
        data.checkIns["2026-10-05"] = DayCheckIn(id: "2026-10-05", sleep: SleepRecord(durationSeconds: 20000, importedFromHealth: true))
        let exported = HealthImport.exportData(data)
        XCTAssertNil(exported.records[walk.id]?.health); XCTAssertNil(exported.checkIns["2026-10-05"]?.sleep)
        XCTAssertEqual(exported.records[walk.id]?.activeMinutes, 0)
        XCTAssertNotNil(data.records[walk.id]?.health)
        data.settings.includeHealthInExports = true; XCTAssertNotNil(HealthImport.exportData(data).records[walk.id]?.health)
    }
    func testNewNotificationPlanDoesNotSpamEveryHourAndHasRoutes() {
        let lesson = event("lezione", .tutoring, 10, 11)
        var data = AppData(); data.settings.repeatMissedNotifications = false
        let notifications = NotificationPlan.requests(events: [lesson], data: data, now: lesson.start.addingTimeInterval(-3600))
        XCTAssertEqual(notifications.filter { $0.eventID == lesson.id }.count, 2)
        XCTAssertFalse(notifications.contains { $0.id == "event-lezione-1" })
        XCTAssertEqual(notifications.first(where: { $0.id == "evening-2026-10-05" })?.destination, "diary")
    }
    func testOldDataDecodesWithoutNewOptionalFields() throws {
        let data = try BackupCodec.decode(BackupCodec.encode(AppData()))
        XCTAssertNil(data.decisions); XCTAssertNil(data.activityDrafts); XCTAssertNil(data.settings.healthEnabled)
        XCTAssertNil(data.settings.includeHealthInExports)
    }
    func testShorteningRequiresExplicitPermissionNotADefaultMinimum() {
        let study = event("studio", .study, 8, 10), fixed = event("lezione", .tutoring, 13, 15)
        var data = AppData(); var rule = EventRule.defaultRule(for: study); rule.travelConfirmed = true
        data.rules[study.id] = rule
        let now = event("adesso", .other, 12, 13).start
        let full = Planner.recover(study, events: [fixed], data: data, now: now, days: 1)
        XCTAssertEqual(full.first?.start, fixed.end)
        data.rules[study.id]?.compressionApproved = true
        let shortened = Planner.recover(study, events: [fixed], data: data, now: now, days: 1)
        XCTAssertEqual(shortened.first?.start, now)
        XCTAssertEqual(shortened.first?.end, fixed.start)
    }
    func testLongPausedWorkoutDoesNotMatchAShortSlot() {
        let slot = event("camminata", .workout, 10, 11)
        let summary = HealthWorkoutSummary(id: "paused", start: slot.start, end: slot.start.addingTimeInterval(3 * 3600), type: "walk", durationSeconds: 1800)
        XCTAssertTrue(HealthImport.candidates(summary, events: [slot]).isEmpty)
    }
    func testUnsupportedWorkoutDoesNotCompleteGym() {
        let gym = event("palestra", .workout, 10, 11)
        let summary = HealthWorkoutSummary(id: "run", start: gym.start, end: gym.end, type: "unsupported", durationSeconds: 3600)
        XCTAssertTrue(HealthImport.candidates(summary, events: [gym]).isEmpty)
    }
    func testSleepSubtractsAwakeUnionWithoutDoubleCounting() {
        let start = date("2026-10-05T01:00:00+02:00"), end = date("2026-10-05T08:00:00+02:00")
        let awake = HealthInterval(start: start.addingTimeInterval(3600), end: start.addingTimeInterval(4200))
        let summary = HealthImport.sleep(asleep: [.init(start: start, end: end)], awake: [awake, awake], endingOn: end)
        XCTAssertEqual(summary?.durationSeconds, 7 * 3600 - 600)
        XCTAssertEqual(summary?.awakenings, 1)
    }
    func testCategoryOverrideStaysLocal() {
        let item = event("lezione Sara", .other, 10, 11)
        var data = AppData(); var rule = EventRule.defaultRule(for: item); rule.kindOverride = .tutoring; data.rules[item.id] = rule
        XCTAssertEqual(Planner.effectiveEvents([item], data: data)[0].kind, .tutoring); XCTAssertEqual(item.kind, .other)
    }
}
