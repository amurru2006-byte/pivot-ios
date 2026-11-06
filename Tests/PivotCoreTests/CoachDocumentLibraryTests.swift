import XCTest
@testable import PivotCore

final class CoachDocumentLibraryTests: XCTestCase {
    private let bytes = Data("%PDF-1.4\nSynthetic shared source QA\n%%EOF".utf8)
    private func source() -> CoachDocumentSource {
        .init(document: .init(name: "Metodo QA.pdf", byteCount: bytes.count), kind: .pdf,
            pageCount: 6, sha256: CoachDocumentSource.digest(bytes), importedAt: Date(timeIntervalSince1970: 1_790_000_000))
    }
    private func sample() -> AppData {
        var data = AppData(); data.coachDocuments = [source()]; return data
    }
    func testOneOriginalCanServeSeveralEventsWithoutDuplicatingBackupBytes() throws {
        var data = sample(); let source = try XCTUnwrap(data.coachDocuments?.first)
        let refs = [CoachDocumentReference(sourceID: source.id, pages: [2, 4])]
        for id in ["qa-event-1", "qa-event-2", "qa-event-3"] {
            XCTAssertTrue(CoachDocumentLibrary.attach(refs, to: id, data: &data))
        }
        data.studyPDFs = [source.document.id.uuidString: bytes]
        XCTAssertEqual(StudyFiles.documents(in: data).count, 1)
        XCTAssertEqual(data.coachDocumentEventLinks?.count, 3)
        let decoded = try BackupCodec.decode(BackupCodec.encode(data))
        XCTAssertEqual(decoded.studyPDFs?.count, 1)
        XCTAssertEqual(decoded.coachDocumentEventLinks, data.coachDocumentEventLinks)
    }
    func testAttachIsIdempotentAndNeverReplacesAnExistingEventReference() throws {
        var data = sample(); let id = try XCTUnwrap(data.coachDocuments?.first?.id)
        let refs = [CoachDocumentReference(sourceID: id, pages: [1])]
        XCTAssertTrue(CoachDocumentLibrary.attach(refs, to: "qa-event", data: &data))
        XCTAssertTrue(CoachDocumentLibrary.attach(refs, to: "qa-event", data: &data))
        XCTAssertFalse(CoachDocumentLibrary.attach([.init(sourceID: id, pages: [3])], to: "qa-event", data: &data))
        XCTAssertEqual(data.coachDocumentEventLinks?.count, 1)
        XCTAssertEqual(data.coachDocumentEventLinks?.first?.references, refs)
        XCTAssertFalse(CoachDocumentLibrary.attach(refs, to: "", data: &data))
    }
    func testInvalidPagesDuplicatesAndDanglingSourcesAreRejected() throws {
        let data = sample(); let sources = try XCTUnwrap(data.coachDocuments), id = sources[0].id
        for pages in [[], [0], [7], [1, 1]] {
            XCTAssertFalse(CoachDocumentReference(sourceID: id, pages: pages).isValid(in: sources))
        }
        XCTAssertFalse(CoachDocumentLibrary.validReferences([.init(sourceID: UUID(), pages: [1])], sources: sources))
        XCTAssertFalse(CoachDocumentLibrary.validReferences([.init(sourceID: id, pages: [1]), .init(sourceID: id, pages: [2])], sources: sources))
        var broken = data; broken.coachDocumentEventLinks = [.init(eventID: "qa", references: [.init(sourceID: UUID(), pages: [1])])]
        XCTAssertFalse(CoachDocumentLibrary.valid(broken))
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(broken)))
    }
    func testRestoreKeepsLogicalRoutesAndUsesNewPhysicalFiles() throws {
        var data = sample(); let source = try XCTUnwrap(data.coachDocuments?.first)
        XCTAssertTrue(CoachDocumentLibrary.attach([.init(sourceID: source.id, pages: [2])], to: "qa-event", data: &data))
        data.studyPDFs = [source.document.id.uuidString: bytes]
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let restored = try StudyFiles.installBackup(data, directory: folder)
        let newSource = try XCTUnwrap(restored.coachDocuments?.first)
        XCTAssertNotEqual(newSource.document.id, source.document.id)
        XCTAssertEqual(newSource.id, source.id)
        XCTAssertEqual(try Data(contentsOf: StudyFiles.url(for: newSource.document.id, directory: folder)), bytes)
        XCTAssertEqual(restored.coachDocumentEventLinks, data.coachDocumentEventLinks)
        XCTAssertTrue(CoachDocumentLibrary.valid(restored))
        let route = try XCTUnwrap(CoachDocumentLibrary.url(sourceID: source.id, page: 2, sources: [source]))
        let destination = try XCTUnwrap(CoachDocumentLibrary.destination(route, sources: [newSource]))
        XCTAssertEqual(destination.source.document.id, newSource.document.id)
        XCTAssertEqual(destination.page, 2)
    }
    func testTamperedSharedFileCannotEnterOrReplaceABackup() throws {
        var data = sample(); let source = try XCTUnwrap(data.coachDocuments?.first)
        var changed = bytes; changed[10] = 65
        data.studyPDFs = [source.document.id.uuidString: changed]
        XCTAssertThrowsError(try StudyFiles.validateBackup(data, requireFiles: true))
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(data)))
        data.studyPDFs = [:]
        XCTAssertThrowsError(try StudyFiles.validateBackup(data, requireFiles: true))
    }
    func testDeepLinksRejectForeignSchemesAmbiguousQueriesAndUnknownSources() throws {
        let sources = [source()], id = sources[0].id.uuidString
        for value in ["https://example.invalid/document/" + id + "?page=1",
            "pivot://document/" + id + "?page=1&page=2", "pivot://document/" + id + "?page=01",
            "pivot://document/" + id + "?page=7", "pivot://document/" + id + "?page=1#fragment",
            "pivot://other/" + id + "?page=1", "pivot://user@document/" + id + "?page=1"] {
            XCTAssertNil(CoachDocumentLibrary.destination(try XCTUnwrap(URL(string: value)), sources: sources))
        }
        XCTAssertNil(CoachDocumentLibrary.url(sourceID: UUID(), page: 1, sources: sources))
    }
    func testLegacyBackupsWithoutDocumentLibraryRemainReadable() throws {
        let raw = try BackupCodec.encode(AppData()), decoded = try BackupCodec.decode(raw)
        XCTAssertNil(decoded.coachDocuments); XCTAssertNil(decoded.coachDocumentEventLinks)
        XCTAssertTrue(CoachDocumentLibrary.valid(decoded))
    }
    func testStudyAndChatSourcesShareTheExistingAggregateLimit() throws {
        var data = sample(); let source = try XCTUnwrap(data.coachDocuments?.first)
        var copies = [source]
        for index in 0..<5 {
            var next = self.source(); next.document.name = "QA \(index).pdf"
            next.document.byteCount = StudyFiles.maximumBytes; copies.append(next)
        }
        data.coachDocuments = copies
        XCTAssertFalse(CoachDocumentLibrary.valid(data))
        XCTAssertThrowsError(try StudyFiles.validateBackup(data))
    }
}
