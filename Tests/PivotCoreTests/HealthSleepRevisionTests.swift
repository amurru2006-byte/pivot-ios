import XCTest
@testable import PivotCore

final class HealthSleepRevisionTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_800_000_000)
    private var key: String { PivotDate.key(day) }
    private var initial: HealthSleepSummary {
        .init(start: day.addingTimeInterval(-8 * 3600), end: day, durationSeconds: 7 * 3600, interruptionSeconds: 600, awakenings: 2)
    }
    private func merge(_ summary: HealthSleepSummary, into data: AppData) -> AppData? {
        HealthReconciliation.merge(workouts: [], sleeps: [key: summary], events: [], data: data, now: max(day, summary.end))
    }
    func testRevisedBedtimeAndInterruptionsRefreshEvenWithSameDurationAndWake() throws {
        let before = try XCTUnwrap(merge(initial, into: AppData()))
        var revision = initial; revision.start = initial.start.addingTimeInterval(-600)
        revision.awakenings = 3; revision.interruptionSeconds = 1200
        let after = try XCTUnwrap(merge(revision, into: before))
        XCTAssertEqual(after.checkIns[key]?.sleep?.bedtime, revision.start)
        XCTAssertEqual(after.checkIns[key]?.sleep?.awakenings, 3)
        XCTAssertEqual(after.checkIns[key]?.sleep?.interruptionSeconds, 1200)
        XCTAssertEqual(after.checkIns[key]?.wakeTime, before.checkIns[key]?.wakeTime)
        let report = HealthRefreshReport.make(workouts: [], sleeps: [key: revision], before: before, after: after, readAt: day)
        XCTAssertEqual(report.sleepDaysApplied, 1)
        XCTAssertNil(merge(revision, into: after))
    }
    func testHealthRevisionPreservesSubjectiveScoreAndQuality() throws {
        var before = try XCTUnwrap(merge(initial, into: AppData()))
        before.checkIns[key]?.sleep?.score = 8; before.checkIns[key]?.sleep?.quality = "Valutazione personale QA"
        var revision = initial; revision.durationSeconds -= 600
        let after = try XCTUnwrap(merge(revision, into: before))
        XCTAssertEqual(after.checkIns[key]?.sleep?.durationSeconds, revision.durationSeconds)
        XCTAssertEqual(after.checkIns[key]?.sleep?.score, 8)
        XCTAssertEqual(after.checkIns[key]?.sleep?.quality, "Valutazione personale QA")
        XCTAssertEqual(after.checkIns[key]?.sleep?.importedFromHealth, true)
    }
    func testManualWakeTimeIsNotOverwrittenByRevisedHealthWake() throws {
        var before = try XCTUnwrap(merge(initial, into: AppData()))
        let manual = day.addingTimeInterval(900); before.checkIns[key]?.wakeTime = manual
        var revision = initial; revision.end = day.addingTimeInterval(300)
        let after = try XCTUnwrap(merge(revision, into: before))
        XCTAssertEqual(after.checkIns[key]?.wakeTime, manual)
        XCTAssertEqual(after.checkIns[key]?.healthWakeTime, revision.end)
    }
    func testManualSleepStillWinsAndNoCalendarReceiptOrLocationIsInvented() throws {
        var data = try XCTUnwrap(merge(initial, into: AppData()))
        let manual = SleepRecord(bedtime: day, durationSeconds: 1234, score: 9, quality: "Manuale QA", importedFromHealth: false)
        data.checkIns[key]?.sleep = manual
        XCTAssertNil(merge(initial, into: data))
        XCTAssertEqual(data.checkIns[key]?.sleep, manual)
        XCTAssertTrue(data.records.isEmpty); XCTAssertTrue(data.payments.isEmpty)
        XCTAssertTrue(data.moves.isEmpty); XCTAssertTrue(data.income.isEmpty)
    }
}
