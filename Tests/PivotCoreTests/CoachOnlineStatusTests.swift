import XCTest
@testable import PivotCore

final class CoachOnlineStatusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func failure(_ object: [String: Any], status: Int = 429) throws -> CoachOnlineFailure {
        .parse(status: status, bytes: try JSONSerialization.data(withJSONObject: object), receivedAt: now)
    }
    func testFiveHourQuotaHasCountdownAndNeverPromisesRestoredCredits() throws {
        let value = try failure(["error":"quota_unavailable","retryAfterSeconds":18000,"retryAt":"ignored-server-clock"])
        XCTAssertEqual(value.kind, .quota); XCTAssertEqual(value.remaining(at: now), 18000)
        XCTAssertEqual(value.timingLabel(at: now), "Riprova tra 05:00:00")
        XCTAssertEqual(value.remaining(at: now.addingTimeInterval(1)), 17999)
        XCTAssertTrue(value.timingLabel(at: now.addingTimeInterval(18000))!.contains("prossima richiesta"))
    }
    func testUnknownWaitDoesNotFabricateAResetTime() throws {
        let value = try failure(["error":"quota_unavailable","retryAfterSeconds":NSNull(),"retryAt":NSNull()])
        XCTAssertNil(value.retryAt); XCTAssertTrue(value.timingLabel(at: now)!.contains("non comunica"))
    }
    func testNegativeFractionalHugeBooleanAndStringWaitsAreRejected() throws {
        let invalid: [Any] = [-1, 0, 1.5, 604801, true, "18000"]
        for seconds in invalid {
            XCTAssertNil(try failure(["error":"quota_unavailable","retryAfterSeconds":seconds]).retryAt)
        }
    }
    func testDistinctTimeoutConfigurationAuthenticationAndRateLimitMessages() throws {
        XCTAssertEqual(try failure(["error":"rate_limited","retryAfterSeconds":60]).kind, .rateLimit)
        XCTAssertEqual(try failure(["error":"provider_timeout"], status: 502).kind, .timeout)
        XCTAssertEqual(try failure(["error":"not_configured"], status: 503).kind, .notConfigured)
        XCTAssertEqual(try failure(["error":"unauthorized"], status: 401).kind, .authentication)
        XCTAssertNil(try failure(["error":"provider_unavailable","retryAfterSeconds":60], status: 502).retryAt)
    }
    func testPrivateUpstreamBodiesAndExtraFieldsNeverReachUserMessages() throws {
        let raw = Data("private-appointment-secret-token".utf8)
        let value = CoachOnlineFailure.parse(status: 502, bytes: raw, receivedAt: now)
        XCTAssertFalse(value.errorDescription!.contains("secret"))
        let extra = try failure(["error":"quota_unavailable","message":"private","retryAfterSeconds":18000])
        XCTAssertNil(extra.retryAt); XCTAssertEqual(extra.kind, .unavailable)
        XCTAssertFalse(extra.errorDescription!.contains("private"))
    }
    func testLargeResponsesAreNotParsed() {
        XCTAssertEqual(CoachOnlineFailure.parse(status: 502, bytes: Data(repeating: 65, count: 8193), receivedAt: now).kind, .unavailable)
    }
    func testExpiredCountdownAndSavedStateStayStableAcrossReopening() throws {
        let first = try failure(["error":"quota_unavailable","retryAfterSeconds":18000])
        let saved = try JSONEncoder().encode(first), restored = try JSONDecoder().decode(CoachOnlineFailure.self, from: saved)
        XCTAssertEqual(restored, first); XCTAssertEqual(restored.remaining(at: now.addingTimeInterval(18001)), 0)
    }
    func testOnlyExplicitHttpsWorkerEndpointAndValidTokenCanBeConfigured() {
        let token = String(repeating: "a", count: 43)
        XCTAssertTrue(CoachOnlineConfiguration(endpoint: "https://pivot.account.workers.dev/v1/coach", token: token, consent: true).valid)
        for url in ["http://pivot.account.workers.dev/v1/coach", "https://example.test/v1/coach", "https://workers.dev/v1/coach",
                    "https://evilworkers.dev/v1/coach", "https://user:pass@pivot.account.workers.dev/v1/coach",
                    "https://pivot.account.workers.dev:8080/v1/coach", "https://pivot.account.workers.dev/v1/coach?token=x",
                    "https://pivot.account.workers.dev/v1/coach#x", "https://pivot.account.workers.dev/other"] {
            XCTAssertFalse(CoachOnlineConfiguration(endpoint: url, token: token, consent: true).valid, url)
        }
        XCTAssertFalse(CoachOnlineConfiguration(endpoint: "https://pivot.account.workers.dev/v1/coach", token: token, consent: false).valid)
        XCTAssertFalse(CoachOnlineConfiguration(endpoint: "https://pivot.account.workers.dev/v1/coach", token: "short", consent: true).valid)
    }
}
