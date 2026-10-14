import XCTest
@testable import PivotCore

final class CoachOnlineSetupLinkTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let endpoint = "https://synthetic.workers.dev/v1/coach"
    private let token = String(repeating: "a", count: 43)
    // Fixed Node.js PBKDF2-SHA256/AES-256-GCM vector; synthetic credential only.
    private let payload = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaG8ZUYzDQb2A1ozJPonvVAkuwXAxwIDeq6Nh1vwRlwaESF0K2Dx2VxEcp_Iyc-Ul2vTKWkexnEKPYS6N3"
    private func link(endpoint: String? = nil, token: String? = nil, age: Double = 0,
                      extra: URLQueryItem? = nil) -> URL {
        var parts = URLComponents()
        parts.scheme = "pivot"; parts.host = "coach-setup"
        parts.queryItems = [.init(name: "version", value: "2"),
                            .init(name: "issued", value: String(Int(now.addingTimeInterval(-age).timeIntervalSince1970))),
                            .init(name: "endpoint", value: endpoint ?? self.endpoint),
                            .init(name: "payload", value: token ?? payload)]
        if let extra { parts.queryItems!.append(extra) }
        return parts.url!
    }
    func testFreshImportCarriesOnlyAnUnsavedConfiguration() throws {
        let value = try XCTUnwrap(CoachOnlineSetupLink.parse(link(), now: now))
        XCTAssertEqual(value.endpoint, endpoint)
        XCTAssertTrue(value.isCurrent(at: now))
        let config = try XCTUnwrap(value.configuration(code: "ABCD2-34567", now: now))
        XCTAssertEqual(config.token, token)
        XCTAssertFalse(config.valid) // The user must explicitly enable consent.
    }
    func testFiveMinuteExpiryAndClockSkewAreBounded() {
        for age in [-60.0, 0, 299, 300] { XCTAssertNotNil(CoachOnlineSetupLink.parse(link(age: age), now: now)) }
        for age in [-61.0, 301, 86400] { XCTAssertNil(CoachOnlineSetupLink.parse(link(age: age), now: now)) }
    }
    func testExpiredConfigurationCannotBeSavedLater() throws {
        let value = try XCTUnwrap(CoachOnlineSetupLink.parse(link(), now: now))
        XCTAssertFalse(value.isCurrent(at: now.addingTimeInterval(301)))
    }
    func testDuplicateUnknownAndMissingFieldsAreRejected() {
        XCTAssertNil(CoachOnlineSetupLink.parse(link(extra: .init(name: "payload", value: payload)), now: now))
        XCTAssertNil(CoachOnlineSetupLink.parse(link(extra: .init(name: "consent", value: "true")), now: now))
        var parts = URLComponents(url: link(), resolvingAgainstBaseURL: false)!
        parts.queryItems!.removeLast()
        XCTAssertNil(CoachOnlineSetupLink.parse(parts.url!, now: now))
    }
    func testUntrustedTargetsAndInsecureEndpointsAreRejected() {
        for endpoint in ["http://synthetic.workers.dev/v1/coach", "https://other.example/v1/coach",
                         "https://synthetic.workers.dev/v1/coach?token=private", "https://secret@synthetic.workers.dev/v1/coach"] {
            XCTAssertNil(CoachOnlineSetupLink.parse(link(endpoint: endpoint), now: now))
        }
        for token in ["short", String(repeating: "a", count: 231), String(repeating: "a", count: 115) + " "] {
            XCTAssertNil(CoachOnlineSetupLink.parse(link(token: token), now: now))
        }
    }
    func testSchemeHostPathCredentialsFragmentAndPortMustMatchExactly() {
        let mutations: [(inout URLComponents) -> Void] = [
            { $0.scheme = "https" }, { $0.host = "workout" }, { $0.path = "/extra" },
            { $0.user = "user" }, { $0.fragment = "extra" }, { $0.port = 443 }
        ]
        for mutate in mutations {
            var parts = URLComponents(url: link(), resolvingAgainstBaseURL: false)!
            mutate(&parts)
            XCTAssertNil(CoachOnlineSetupLink.parse(parts.url!, now: now))
        }
    }
    func testMalformedTimestampVersionAndOversizedImportAreRejected() {
        for stamp in ["NaN", "Infinity", "-1", "1800000000.1", String(repeating: "1", count: 16)] {
            var parts = URLComponents(url: link(), resolvingAgainstBaseURL: false)!
            parts.queryItems![1].value = stamp
            XCTAssertNil(CoachOnlineSetupLink.parse(parts.url!, now: now))
        }
        var parts = URLComponents(url: link(), resolvingAgainstBaseURL: false)!
        parts.queryItems![0].value = "1" // Old plaintext imports must not be accepted.
        XCTAssertNil(CoachOnlineSetupLink.parse(parts.url!, now: now))
        XCTAssertNil(CoachOnlineSetupLink.parse(link(token: String(repeating: "a", count: 2049)), now: now))
    }
    func testWrongCodeOrExpiredCapsuleNeverReturnsCredential() throws {
        let value = try XCTUnwrap(CoachOnlineSetupLink.parse(link(), now: now))
        for code in ["short", "ABCD234568", "ABCD23456I", "ABCD23456O"] {
            XCTAssertNil(value.configuration(code: code, now: now))
        }
        XCTAssertNil(value.configuration(code: "ABCD234567", now: now.addingTimeInterval(301)))
    }
    func testEndpointTimestampAndCiphertextAreAuthenticated() throws {
        let changedEndpoint = try XCTUnwrap(CoachOnlineSetupLink.parse(link(endpoint: "https://tampered.workers.dev/v1/coach"), now: now))
        XCTAssertNil(changedEndpoint.configuration(code: "ABCD234567", now: now))
        let changedTime = try XCTUnwrap(CoachOnlineSetupLink.parse(link(age: 1), now: now))
        XCTAssertNil(changedTime.configuration(code: "ABCD234567", now: now))
        let changedPayload = try XCTUnwrap(CoachOnlineSetupLink.parse(link(token: "B" + payload.dropFirst()), now: now))
        XCTAssertNil(changedPayload.configuration(code: "ABCD234567", now: now))
    }
}
