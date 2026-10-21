import XCTest
@testable import PivotCore

final class HealthWorkoutCacheTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var summary: HealthWorkoutSummary {
        .init(id: "qa-cache", start: now.addingTimeInterval(-3600), end: now, type: "walk", durationSeconds: 3600,
              distanceKM: 4, activeCalories: 200, averageBPM: 100)
    }
    func testFreshCacheAvoidsExtraQueryButForceAlwaysRechecks() {
        let cache = HealthWorkoutCacheEntry(summary: summary, heartRateReadAt: now)
        XCTAssertFalse(cache.needsHeartRate(for: summary, now: now.addingTimeInterval(60), force: false))
        XCTAssertTrue(cache.needsHeartRate(for: summary, now: now.addingTimeInterval(60), force: true))
    }
    func testSameUUIDAndTimingButChangedTotalsInvalidateCache() {
        let cache = HealthWorkoutCacheEntry(summary: summary, heartRateReadAt: now)
        for keyPath in [\HealthWorkoutSummary.distanceKM, \.activeCalories, \.elevationM] {
            var fresh = summary; fresh[keyPath: keyPath] = 50
            XCTAssertTrue(cache.needsHeartRate(for: fresh, now: now, force: false))
        }
    }
    func testMissingHeartRateRetriesAfterFiveMinutesAndPresentAfterFifteen() {
        var cache = HealthWorkoutCacheEntry(summary: summary, heartRateReadAt: now)
        XCTAssertFalse(cache.needsHeartRate(for: summary, now: now.addingTimeInterval(899), force: false))
        XCTAssertTrue(cache.needsHeartRate(for: summary, now: now.addingTimeInterval(900), force: false))
        cache.summary.averageBPM = nil
        XCTAssertFalse(cache.needsHeartRate(for: summary, now: now.addingTimeInterval(299), force: false))
        XCTAssertTrue(cache.needsHeartRate(for: summary, now: now.addingTimeInterval(300), force: false))
    }
    func testClockRollbackAndUnfinishedQueryDoNotAppearFresh() {
        var cache = HealthWorkoutCacheEntry(summary: summary, heartRateReadAt: now)
        XCTAssertTrue(cache.needsHeartRate(for: summary, now: now.addingTimeInterval(-1), force: false))
        cache.heartRateReadAt = nil
        XCTAssertTrue(cache.needsHeartRate(for: summary, now: now, force: false))
    }
    func testCachedHeartRateNotReusedAcrossChangedTimingOrIdentity() {
        let cache = HealthWorkoutCacheEntry(summary: summary, heartRateReadAt: now)
        var fresh = summary; fresh.start = fresh.start.addingTimeInterval(1)
        XCTAssertNil(cache.compatibleHeartRate(for: fresh))
        fresh = summary; fresh.id = "qa-other"
        XCTAssertNil(cache.compatibleHeartRate(for: fresh))
        XCTAssertEqual(cache.compatibleHeartRate(for: summary), 100)
    }
}
