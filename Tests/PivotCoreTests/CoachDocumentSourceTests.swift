import XCTest
@testable import PivotCore

final class CoachDocumentSourceTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-06T12:00:00+01:00")!
    // Envelope validation only: iOS PDFKit rendering has separate native tests.
    private let bytes = Data("%PDF-1.4\nSynthetic document envelope QA\n%%EOF".utf8)
    private func source(pages: Int = 12) -> CoachDocumentSource {
        .init(document: .init(name: "Documento QA.pdf", byteCount: bytes.count), kind: .pdf,
              pageCount: pages, sha256: CoachDocumentSource.digest(bytes), importedAt: now)
    }
    private func packet() -> CoachDocumentPacket {
        let document = source()
        return .init(createdAt: now, instruction: "Prepara le scadenze, senza modificare il Calendario",
            sources: [document], pages: [.init(sourceID: document.id, number: 3,
                text: "Scadenza QA: 6 novembre 2026 alle 23:44.\nSeconda riga QA.", reading: .text)])
    }
    func testImmutableSourceRejectsTamperingAndUnsafeMetadata() {
        let original = source(); XCTAssertTrue(original.matches(bytes))
        var edited = bytes; edited[10] = 65
        XCTAssertFalse(original.matches(edited))
        for name in ["", "../source.pdf", "C:\\source.pdf", "source\nQA.pdf"] {
            var item = original; item.document.name = name; XCTAssertFalse(item.isValid)
        }
        var item = original; item.sha256 = String(repeating: "g", count: 64); XCTAssertFalse(item.isValid)
        item = original; item.pageCount = 501; XCTAssertFalse(item.isValid)
    }
    func testRestoreCanAllocateFreshPhysicalIDWithoutChangingStableSourceIdentity() throws {
        let original = source(); var restored = original; restored.document.id = UUID()
        XCTAssertTrue(restored.matches(bytes)); XCTAssertEqual(restored.id, original.id)
        XCTAssertNotEqual(restored.document.id, original.document.id)
        let roundTrip = try JSONDecoder().decode(CoachDocumentSource.self, from: JSONEncoder().encode(restored))
        XCTAssertEqual(roundTrip, restored)
    }
    func testLibraryRejectsDuplicateLogicalAndPhysicalIdentitiesAndAggregateOverage() {
        let original = source()
        XCTAssertFalse(CoachDocumentSource.validLibrary([original, original]))
        var second = original; second.id = UUID()
        XCTAssertFalse(CoachDocumentSource.validLibrary([original, second]))
        let large = (0..<6).map { _ -> CoachDocumentSource in
            var value = source(); value.document.byteCount = StudyFiles.maximumBytes; return value
        }
        XCTAssertFalse(CoachDocumentSource.validLibrary(large))
        second.document.id = UUID(); XCTAssertTrue(CoachDocumentSource.validLibrary([original, second]))
    }
    func testPacketOnlyCoversExplicitPagesAndDisclosesUnreadableContent() {
        var value = packet(); let source = value.sources[0]
        XCTAssertTrue(value.isValid); XCTAssertEqual(value.coverage(for: source.id), "Pagine selezionate: 3 di 12.")
        value.pages.append(.init(sourceID: source.id, number: 5, text: "", reading: .unreadable))
        XCTAssertTrue(value.isValid); XCTAssertEqual(value.unreadablePages, 1)
        XCTAssertTrue(value.coverage(for: source.id)!.contains("non leggibili"))
        XCTAssertFalse(value.coverage(for: source.id)!.contains("tutto il documento"))
    }
    func testGroundingChecksSelectedSourcePageAndQuotationWithoutClaimingInterpretation() {
        let value = packet(), id = value.sources[0].id
        XCTAssertTrue(CoachDocumentCitation(sourceID: id, page: 3, quote: "23:44. Seconda riga QA.").isGrounded(in: value))
        XCTAssertFalse(CoachDocumentCitation(sourceID: id, page: 4, quote: "23:44").isGrounded(in: value))
        XCTAssertFalse(CoachDocumentCitation(sourceID: UUID(), page: 3, quote: "23:44").isGrounded(in: value))
        XCTAssertFalse(CoachDocumentCitation(sourceID: id, page: 3, quote: "7 novembre").isGrounded(in: value))
        XCTAssertFalse(CoachDocumentCitation(sourceID: id, page: 3, quote: "  ").isGrounded(in: value))
        var malformed = value; malformed.pages.append(value.pages[0])
        XCTAssertFalse(CoachDocumentCitation(sourceID: id, page: 3, quote: "23:44").isGrounded(in: malformed))
    }
    func testRepeatedOrForeignPagesCannotBeAcceptedAsAValidSelection() {
        let original = packet(); var value = original; value.pages.append(original.pages[0]); XCTAssertFalse(value.isValid)
        value = original; value.pages[0].sourceID = UUID(); XCTAssertFalse(value.isValid)
        value = original; value.pages[0].number = 13; XCTAssertFalse(value.isValid)
        value = original; value.sources[0].importedAt = now.addingTimeInterval(1); XCTAssertFalse(value.isValid)
    }
    func testSnapshotRejectsChangedOrMissingSourceWithoutInvalidatingUnrelatedImports() {
        let value = packet(); XCTAssertTrue(value.isCurrent(in: value.sources + [source()]))
        XCTAssertFalse(value.isCurrent(in: []))
        var library = value.sources; library[0].sha256 = String(repeating: "a", count: 64)
        XCTAssertFalse(value.isCurrent(in: library)); XCTAssertFalse(value.isCurrent(in: value.sources + value.sources))
    }
    func testPageConfidenceAndTextBoundsRejectMalformedOrSilentPartialReadings() {
        let original = packet().pages[0]; var page = original
        page.reading = .ocr; XCTAssertFalse(page.isValid)
        page.ocrConfidence = 0.7; XCTAssertTrue(page.isValid)
        page.ocrConfidence = .nan; XCTAssertFalse(page.isValid)
        page = original; page.reading = .unreadable; XCTAssertFalse(page.isValid)
        page = original; page.text = String(repeating: "a", count: 20_001); XCTAssertFalse(page.isValid)
    }
}
