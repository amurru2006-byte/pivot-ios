import Foundation
import XCTest
@testable import PivotCore

final class SignatureRenewalTests: XCTestCase {
    private let bundleID = "app.example.pivot"
    private let expiry = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    func testReadsDateFromEmbeddedCMSProfile() throws {
        XCTAssertEqual(
            SignatureRenewal.profileExpiry(in: try profile(), bundleID: bundleID),
            expiry
        )
    }

    func testDoesNotUseProfileFromAnotherAppOrWithoutProvisionedDevices() throws {
        XCTAssertNil(SignatureRenewal.profileExpiry(in: try profile(), bundleID: bundleID + ".widget"))
        XCTAssertNil(SignatureRenewal.profileExpiry(in: try profile(devices: []), bundleID: bundleID))
    }

    func testRejectsTruncatedOversizedAndWrongContentTypes() throws {
        let valid = try profile()
        XCTAssertNil(SignatureRenewal.profileExpiry(in: Data(valid.dropLast()), bundleID: bundleID))
        XCTAssertNil(SignatureRenewal.profileExpiry(in: Data(count: SignatureRenewal.profileByteLimit + 1), bundleID: bundleID))
        XCTAssertNil(SignatureRenewal.profileExpiry(in: try profile(contentType: 0x02), bundleID: bundleID))
        XCTAssertNil(SignatureRenewal.profileExpiry(in: try profile(expiration: "tomorrow"), bundleID: bundleID))
    }

    func testReminderBeginsAtSeventyTwoHoursAndRemainsForAStaleProfile() {
        let start = expiry.addingTimeInterval(-3 * day)
        let deadline = SignatureRenewal.deadline(profileExpiry: expiry, confirmation: nil, now: start)
        XCTAssertFalse(deadline.needsReminder(at: start.addingTimeInterval(-1)))
        XCTAssertTrue(deadline.needsReminder(at: start))
        XCTAssertTrue(deadline.needsReminder(at: expiry.addingTimeInterval(day)))
    }

    func testConfirmedQuickRefreshUsesEstimateAndWarnsAgainBeforeNextExpiry() {
        let now = expiry.addingTimeInterval(-2 * day)
        let confirmation = SignatureRenewal.Confirmation(profileExpiry: expiry, confirmedAt: now)
        let deadline = SignatureRenewal.deadline(profileExpiry: expiry, confirmation: confirmation, now: now)
        XCTAssertEqual(deadline.date, now.addingTimeInterval(7 * day))
        XCTAssertTrue(deadline.estimated)
        XCTAssertFalse(deadline.needsReminder(at: now))
        XCTAssertTrue(deadline.needsReminder(at: now.addingTimeInterval(4 * day)))
    }

    func testChangedProfileOverridesEstimate() {
        let now = expiry.addingTimeInterval(-day)
        let confirmation = SignatureRenewal.Confirmation(profileExpiry: expiry, confirmedAt: now)
        let newExpiry = now.addingTimeInterval(5 * day)
        let deadline = SignatureRenewal.deadline(profileExpiry: newExpiry, confirmation: confirmation, now: now)
        XCTAssertEqual(deadline.date, newExpiry)
        XCTAssertFalse(deadline.estimated)
        XCTAssertFalse(deadline.needsReminder(at: now))
    }

    func testIgnoresConfirmationInTheFutureOrWhenItShortensProfileValidity() {
        let now = expiry.addingTimeInterval(-8 * day)
        for confirmedAt in [now, now.addingTimeInterval(day)] {
            let confirmation = SignatureRenewal.Confirmation(profileExpiry: expiry, confirmedAt: confirmedAt)
            let deadline = SignatureRenewal.deadline(profileExpiry: expiry, confirmation: confirmation, now: now)
            XCTAssertEqual(deadline.date, expiry)
            XCTAssertFalse(deadline.estimated)
        }
    }

    private func profile(devices: [String] = ["synthetic-device"], contentType: UInt8 = 0x01, expiration: Any? = nil) throws -> Data {
        let plist = try PropertyListSerialization.data(fromPropertyList: [
            "ProvisionedDevices": devices,
            "Entitlements": ["application-identifier": "TESTTEAM." + bundleID],
            "ExpirationDate": expiration ?? expiry
        ], format: .xml, options: 0)
        let oid: (UInt8) -> [UInt8] = { suffix in
            self.der(0x06, [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, suffix])
        }
        let payload = der(0xa0, der(0x04, Array(plist)))
        let encapsulated = der(0x30, oid(contentType) + payload)
        let signed = der(0x30, der(0x02, [1]) + der(0x31, []) + encapsulated + der(0x31, []))
        return Data(der(0x30, oid(0x02) + der(0xa0, signed)))
    }

    private func der(_ tag: UInt8, _ value: [UInt8]) -> [UInt8] {
        let count = value.count
        if count < 128 { return [tag, UInt8(count)] + value }
        if count <= 255 { return [tag, 0x81, UInt8(count)] + value }
        return [tag, 0x82, UInt8(count >> 8), UInt8(count & 0xff)] + value
    }
}
