import XCTest
@testable import PivotCore

final class HealthRefreshReportTests: XCTestCase {
    private func event(_ id: String, _ title: String, hour: Int) -> CalendarItem {
        let start = PivotDate.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
        return .init(id: id, eventIdentifier: id, externalIdentifier: nil, calendarIdentifier: "test",
                     calendarTitle: "Test", title: title, start: start, end: start.addingTimeInterval(3600),
                     location: "", notes: "", colorHex: "#000000", isAllDay: false, writable: true,
                     kind: EventKind.classify(title: title, calendar: "Test"))
    }

    func testReportExplainsEveryAppliedHealthChange() {
        let gym = event("gym", "Palestra", hour: 10)
        let sleep = event("sleep", "Sonno", hour: 6)
        let workout = HealthWorkoutSummary(id: "hk", start: gym.start, end: gym.end, type: "strength", durationSeconds: 3600)
        let sleepSummary = HealthSleepSummary(start: sleep.start, end: sleep.end, durationSeconds: 3500,
                                              interruptionSeconds: nil, awakenings: nil)
        var after = AppData()
        HealthImport.apply(workout, to: gym, data: &after)
        after.checkIns["today"] = .init(id: "today", wakeTime: sleep.end,
                                        sleep: .init(bedtime: sleep.start, durationSeconds: 3500, importedFromHealth: true),
                                        healthWakeTime: sleep.end)
        var sleepRecord = EventRecord(id: sleep.id, snapshot: sleep)
        sleepRecord.status = .completed; sleepRecord.actualStart = sleep.start; sleepRecord.actualEnd = sleep.end
        sleepRecord.healthSleep = after.checkIns["today"]?.sleep
        after.records[sleep.id] = sleepRecord
        after.workoutReviews = [.init(workout: workout, eventIDs: [gym.id])]

        let report = HealthRefreshReport.make(workouts: [workout], sleeps: ["today": sleepSummary],
                                              before: AppData(), after: after, readAt: Date())
        XCTAssertEqual(report.workoutSamples, 1)
        XCTAssertEqual(report.sleepDays, 1)
        XCTAssertEqual(report.workoutsApplied, 1)
        XCTAssertEqual(report.sleepDaysApplied, 1)
        XCTAssertEqual(report.sleepEventsCompleted, 1)
        XCTAssertEqual(report.pendingDecisions, 1)
        XCTAssertEqual(report.appliedChanges, 3)
    }

    func testReportDoesNotClaimUnchangedDataWasAppliedAgain() {
        let gym = event("gym", "Palestra", hour: 10)
        let workout = HealthWorkoutSummary(id: "hk", start: gym.start, end: gym.end, type: "strength", durationSeconds: 3600)
        var data = AppData(); HealthImport.apply(workout, to: gym, data: &data)
        let report = HealthRefreshReport.make(workouts: [workout], sleeps: [:], before: data, after: data, readAt: Date())
        XCTAssertEqual(report.appliedChanges, 0)
        XCTAssertEqual(report.pendingDecisions, 0)
    }
}
