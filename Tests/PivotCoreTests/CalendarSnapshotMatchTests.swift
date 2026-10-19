import XCTest
@testable import PivotCore

final class CalendarSnapshotMatchTests: XCTestCase {
    private let time = ISO8601DateFormatter().date(from: "2026-10-18T12:00:00Z")!
    private func backup() -> CalendarEventBackup {
        let item = CalendarItem(id: "logical-test", eventIdentifier: "native-test", externalIdentifier: "external-test",
            calendarIdentifier: "calendar-test", calendarTitle: "Personale Test", title: "Evento Test", start: time.addingTimeInterval(0.375),
            end: time.addingTimeInterval(3600.375), location: "Luogo Test", notes: "Nota Test", colorHex: "123456", isAllDay: false,
            writable: true, kind: .other, sourceIdentifier: "source-test", sourceTitle: "Account Test",
            calendarModifiedAt: time.addingTimeInterval(0.625), recurring: false, calendarCreatedAt: time.addingTimeInterval(-3600.125))
        return .init(snapshot: item, originalNotes: "Nota Test", url: "https://example.test/info", timeZoneIdentifier: "Europe/Rome",
                     availabilityRawValue: 0, alarms: [.init(absoluteDate: time.addingTimeInterval(0.875), relativeSeconds: nil)])
    }
    func testPersistedWholeSecondSnapshotMatchesTheSameFractionalSDKRevision() throws {
        let original = backup()
        var data = AppData()
        data.calendarActionArchive = [.init(batchID: UUID(), actionID: UUID(), kind: .delete, original: original, preparedAt: time)]
        let restored = try BackupCodec.decode(BackupCodec.encodeCompact(data))
        let saved = try XCTUnwrap(restored.calendarActionArchive?.first?.original)
        XCTAssertNotEqual(saved, original, "Legacy ISO8601 persistence loses subsecond precision")
        XCTAssertTrue(CalendarSnapshotMatch.backup(saved, original))
        XCTAssertTrue(CalendarSnapshotMatch.backup(original, saved))
    }
    func testRealTimeContentAndHiddenMetadataChangesAreNotPrecisionDifferences() {
        let original = backup()
        var changed = original; changed.snapshot.start.addTimeInterval(60)
        XCTAssertFalse(CalendarSnapshotMatch.backup(original, changed))
        changed = original; changed.snapshot.title = "Titolo esterno"
        XCTAssertFalse(CalendarSnapshotMatch.backup(original, changed))
        changed = original; changed.snapshot.notes = "Nuove note"; changed.originalNotes = "Nuove note"
        XCTAssertFalse(CalendarSnapshotMatch.backup(original, changed))
        changed = original; changed.url = "https://example.test/changed"
        XCTAssertFalse(CalendarSnapshotMatch.backup(original, changed))
        changed = original; changed.alarms[0].absoluteDate?.addTimeInterval(2)
        XCTAssertFalse(CalendarSnapshotMatch.backup(original, changed))
    }
    func testCalendarPresentationIsNotAnEventEditButAnotherAccountIs() {
        let original = backup(); var changed = original
        changed.snapshot.calendarTitle = "Nuovo nome"; changed.snapshot.sourceTitle = "Nuova etichetta"
        changed.snapshot.colorHex = "654321"; changed.snapshot.kind = .social
        XCTAssertTrue(CalendarSnapshotMatch.backup(original, changed))
        changed.snapshot.sourceIdentifier = "different-account"
        XCTAssertFalse(CalendarSnapshotMatch.backup(original, changed))
    }
    func testOnlyKnownUIDInTheSameCalendarCanRefreshTheNativeIdentity() {
        let original = backup(); var changed = original
        changed.snapshot.eventIdentifier = "new-sdk-native"
        XCTAssertTrue(CalendarSnapshotMatch.backup(original, changed))
        changed.snapshot.externalIdentifier = nil
        XCTAssertFalse(CalendarSnapshotMatch.backup(original, changed))
        changed = original; changed.snapshot.calendarIdentifier = "another-calendar"
        XCTAssertFalse(CalendarSnapshotMatch.backup(original, changed))
        changed = original; changed.snapshot.recurring = true
        XCTAssertFalse(CalendarSnapshotMatch.backup(original, changed))
    }
    func testSameNativeIdentityCanAcquireItsInitialUIDButNotBecomeAnotherUID() {
        var initial = backup(), synchronized = backup()
        initial.snapshot.externalIdentifier = nil
        XCTAssertTrue(CalendarSnapshotMatch.backup(initial, synchronized))
        synchronized.snapshot.externalIdentifier = "unrelated-uid"
        XCTAssertFalse(CalendarSnapshotMatch.backup(backup(), synchronized))
        synchronized = backup(); synchronized.snapshot.calendarModifiedAt?.addTimeInterval(2)
        XCTAssertFalse(CalendarSnapshotMatch.backup(backup(), synchronized))
    }
    func testConfirmedUndoMayAcceptOnlySyncTimestampAdvanceNotPayloadChanges() {
        let original = backup(); var synchronized = original
        synchronized.snapshot.calendarModifiedAt?.addTimeInterval(10)
        XCTAssertFalse(CalendarSnapshotMatch.backup(original, synchronized))
        XCTAssertTrue(CalendarSnapshotMatch.backup(original, synchronized, requireModificationDate: false))
        synchronized.snapshot.location = "Nuovo luogo"
        XCTAssertFalse(CalendarSnapshotMatch.backup(original, synchronized, requireModificationDate: false))
        synchronized = original; synchronized.url = "https://example.test/changed"
        XCTAssertFalse(CalendarSnapshotMatch.backup(original, synchronized, requireModificationDate: false))
    }
}
