import XCTest
@testable import PivotCore

final class DayRecoveryReviewTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-10-14T12:00:00+02:00")!
    private func event(_ id: String, offset: Double = -7200) -> CalendarItem {
        .init(id: id, eventIdentifier: id, calendarIdentifier: "test", calendarTitle: "Test", title: id,
              start: now.addingTimeInterval(offset), end: now.addingTimeInterval(offset + 3600),
              location: "", notes: "", colorHex: "#000000", isAllDay: false, writable: true, kind: .workout)
    }
    func testOverdueOrStartedUnrecordedEventsNeedReviewNotAutomaticSkip() {
        let events = [event("expired"), event("current", offset: -1800), event("future", offset: 3600)]
        let result = DayRecoveryReview.make(events: events, data: AppData(), preferences: ["expired": .recover], now: now)
        XCTAssertEqual(result.map(\.state), [.needsReview, .needsReview, .planned])
    }
    func testExplicitOutcomesAndRecoveryPreferencesRemainDistinct() {
        let states: [Completion] = [.completed, .running, .partial, .skipped, .skipped, .skipped, .skipped]
        let events = states.indices.map { event("e\($0)") }
        var data = AppData()
        for (index, state) in states.enumerated() { data.records[events[index].id] = .init(id: events[index].id, snapshot: events[index], status: state) }
        let prefs: [String: RecoveryPreference] = ["e3": .recover, "e4": .optional, "e5": .doNotRecover]
        XCTAssertEqual(DayRecoveryReview.make(events: events, data: data, preferences: prefs, now: now).map(\.state),
            [.completed, .running, .partialNeedsReview, .recoveryCandidate, .optionalRecovery, .notToRecover, .recoveryPreferenceMissing])
    }
    func testSleepOverlapExplainsReviewWithoutFabricatingSkippedOrCompletedOutcomes() throws {
        var data = AppData(); data.settings.healthEnabled = true
        let wake = now.addingTimeInterval(-600), bedtime = now.addingTimeInterval(-36000)
        data.checkIns[PivotDate.key(now)] = .init(id: PivotDate.key(now), wakeTime: wake,
            sleep: .init(bedtime: bedtime, importedFromHealth: true), healthWakeTime: wake)
        let value = try XCTUnwrap(DayRecoveryReview.make(events: [event("unknown")], data: data, preferences: [:], now: now).first)
        XCTAssertTrue(value.overlapsRecordedSleep); XCTAssertEqual(value.state, .needsReview)
        XCTAssertNil(data.records["unknown"]); XCTAssertEqual(DayWakeContext.make(data: data, now: now)?.source, .health)
    }
    func testManualWakeOverridesHealthAndOldFutureOrDisconnectedWakeIsIgnored() {
        var data = AppData(); data.settings.healthEnabled = true
        let key = PivotDate.key(now), health = now.addingTimeInterval(-1800), manual = now.addingTimeInterval(-600)
        data.checkIns[key] = .init(id: key, wakeTime: manual, sleep: .init(importedFromHealth: true), healthWakeTime: health)
        XCTAssertEqual(DayWakeContext.make(data: data, now: now)?.source, .manual)
        data.checkIns[key]?.wakeTime = health; data.settings.healthEnabled = false
        XCTAssertNil(DayWakeContext.make(data: data, now: now))
        data.checkIns[key]?.wakeTime = now.addingTimeInterval(600)
        XCTAssertNil(DayWakeContext.make(data: data, now: now))
        data.checkIns[key]?.wakeTime = now.addingTimeInterval(-86400)
        XCTAssertNil(DayWakeContext.make(data: data, now: now))
    }
    func testDeletedEventsAreNotRecreatedFromDiaryAndPendingMovesAreVisible() {
        let gone = event("gone"), current = event("current")
        var data = AppData(); data.records[gone.id] = .init(id: gone.id, snapshot: gone, status: .skipped)
        data.moves = [.init(source: current, proposedStart: now.addingTimeInterval(3600), proposedEnd: now.addingTimeInterval(7200))]
        let result = DayRecoveryReview.make(events: [current], data: data, preferences: [:], now: now)
        XCTAssertEqual(result.map(\.id), ["current"]); XCTAssertTrue(result[0].hasPendingMove)
        XCTAssertEqual(result[0].state, .planned)
    }
    func testReadOnlyReviewIsRepeatableAndRetainsSevenDayBacklog() throws {
        let recent = event("recent", offset: -6 * 86400), old = event("old", offset: -8 * 86400)
        let data = AppData(), before = try BackupCodec.encode(data)
        let first = DayRecoveryReview.make(events: [recent, old], data: data, preferences: [:], now: now)
        XCTAssertEqual(first.map(\.id), ["recent"])
        XCTAssertEqual(first, DayRecoveryReview.make(events: [recent, old], data: data, preferences: [:], now: now))
        XCTAssertEqual(before, try BackupCodec.encode(data))
    }
}
