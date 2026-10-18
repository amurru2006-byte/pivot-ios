import XCTest
@testable import PivotCore

final class CoachMemoryExpiryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    func testTemporaryInformationExpiresWithoutDeletingItsAuditRecord() {
        let value = CoachMemory(text: "Preferenza sintetica", createdAt: now, expiresAt: now.addingTimeInterval(60))
        XCTAssertTrue(value.isActive(at: now)); XCTAssertFalse(value.isActive(at: now.addingTimeInterval(60)))
        XCTAssertFalse(value.isActive(at: now.addingTimeInterval(-1))); XCTAssertEqual(value.text, "Preferenza sintetica")
    }
    func testLegacyMemoryHasNoInventedExpiry() throws {
        let raw = "{\"id\":\"00000000-0000-0000-0000-000000000001\",\"text\":\"Nota QA\",\"createdAt\":0}"
        let value = try JSONDecoder().decode(CoachMemory.self, from: Data(raw.utf8))
        XCTAssertNil(value.expiresAt); XCTAssertTrue(value.isActive(at: now))
    }
    func testInvalidExpiryAndOversizedInformationAreRejected() {
        XCTAssertFalse(CoachMemory(text: "QA", createdAt: now, expiresAt: now).isValid)
        XCTAssertFalse(CoachMemory(text: "QA", createdAt: now, expiresAt: Date(timeIntervalSince1970: .infinity)).isValid)
        XCTAssertFalse(CoachMemory(text: "  ", createdAt: now).isValid)
        XCTAssertFalse(CoachMemory(text: String(repeating: "x", count: 1501), createdAt: now).isValid)
    }
    func testBackupPreservesTemporaryInformationAndRejectsReversedDates() throws {
        var data = AppData(); var coach = CoachState()
        coach.memories = [.init(text: "Nota temporanea QA", createdAt: now, expiresAt: now.addingTimeInterval(60))]
        data.coach = coach
        let restored = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertEqual(restored.coach?.memories, coach.memories)
        data.coach?.memories[0].expiresAt = now.addingTimeInterval(-1)
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(data)))
    }
}
