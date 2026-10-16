import XCTest
@testable import PivotCore

final class EncryptedBackupTests: XCTestCase {
    // Deliberately public fixtures, never a real password or an imported backup.
    private let password = "Only a synthetic test password 42!"

    func testEncryptedRoundTripPreservesLedgerAndContainsNoCleartext() throws {
        var data = AppData()
        data.clients = [.init(name: "Contatto sintetico riservato", rateCents: 1500)]
        let key = try EncryptedBackup.prepare(password: password, confirmation: password)
        let bytes = try BackupCodec.encode(data)
        let archive = try EncryptedBackup.seal(bytes, using: key)
        XCTAssertNil(archive.range(of: Data("Contatto sintetico riservato".utf8)))
        XCTAssertEqual(try EncryptedBackup.decoded(archive, password: password).clients.first?.name, data.clients.first?.name)
    }

    func testFreshNonceAndFreshPasswordConfiguration() throws {
        let key = try EncryptedBackup.prepare(password: password, confirmation: password)
        let clear = Data("Synthetic contents".utf8)
        let first = try EncryptedBackup.seal(clear, using: key)
        let second = try EncryptedBackup.seal(clear, using: key)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try EncryptedBackup.open(first, using: key), clear)
        XCTAssertEqual(try EncryptedBackup.open(second, using: key), clear)
        let other = try EncryptedBackup.prepare(password: password, confirmation: password)
        XCTAssertNotEqual(key.identifier, other.identifier)
        XCTAssertThrowsError(try EncryptedBackup.open(first, using: other))
    }

    func testWrongPasswordAndMissingPasswordFailClosed() throws {
        let key = try EncryptedBackup.prepare(password: password, confirmation: password)
        let archive = try EncryptedBackup.seal(BackupCodec.encode(AppData()), using: key)
        XCTAssertThrowsError(try EncryptedBackup.decoded(archive))
        XCTAssertThrowsError(try EncryptedBackup.decoded(archive, password: "Another synthetic password"))
    }

    func testTamperedPayloadTagAndHeaderAreRejected() throws {
        let key = try EncryptedBackup.prepare(password: password, confirmation: password)
        let archive = try EncryptedBackup.seal(BackupCodec.encode(AppData()), using: key)
        for index in [0, 24, archive.count - 17, archive.count - 1] {
            var altered = archive; altered[index] ^= 1
            XCTAssertThrowsError(try EncryptedBackup.decoded(altered, password: password))
        }
        XCTAssertThrowsError(try EncryptedBackup.decoded(Data(archive.prefix(30)), password: password))
    }

    func testWeakMismatchAndNulPasswordsAreRejected() {
        for text in ["short", String(repeating: " ", count: 15), "long password\0suffix", String(repeating: "x", count: 257)] {
            XCTAssertThrowsError(try EncryptedBackup.prepare(password: text, confirmation: text))
        }
        XCTAssertThrowsError(try EncryptedBackup.prepare(password: password, confirmation: password + "x"))
    }

    func testUnicodeNormalizationAndMeaningfulSpaces() throws {
        let composed = "A synthetic caf\u{00e9} password"
        let decomposed = "A synthetic cafe\u{0301} password"
        let key = try EncryptedBackup.prepare(password: composed, confirmation: decomposed)
        let archive = try EncryptedBackup.seal(Data("ok".utf8), using: key)
        XCTAssertEqual(try EncryptedBackup.open(archive, password: decomposed), Data("ok".utf8))
        XCTAssertThrowsError(try EncryptedBackup.open(archive, password: composed + " "))
    }

    func testLegacyJSONIsStillReadableAndUnchanged() throws {
        var data = AppData(); data.ledger = AnnualLedger(openingCents: ["2026": 12345])
        let bytes = try BackupCodec.encode(data), copy = bytes
        XCTAssertEqual(try EncryptedBackup.decoded(bytes).ledger?.openingCents["2026"], 12345)
        XCTAssertEqual(bytes, copy)
    }

    func testInvalidArchiveAndInvalidKeyAreRejected() {
        XCTAssertThrowsError(try EncryptedBackup.decoded(Data("Not a Pivot archive".utf8)))
        XCTAssertThrowsError(try EncryptedBackup.seal(Data(), using: .init(salt: Data(), key: Data())))
    }

    func testBoundedReaderDoesNotChangeOriginalFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pivot-backup-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let original = try BackupCodec.encode(AppData())
        try original.write(to: url, options: .atomic)
        XCTAssertEqual(try EncryptedBackup.read(url), original)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
}
