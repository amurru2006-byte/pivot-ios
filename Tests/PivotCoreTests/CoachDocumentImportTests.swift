import XCTest
@testable import PivotCore

final class CoachDocumentImportTests: XCTestCase {
    private func source(_ name: String = "QA.pdf") -> CoachDocumentSource {
        let bytes = Data(("%PDF-1.4\nSYNTHETIC " + name + "\n%%EOF").utf8)
        return .init(document: .init(name: name, byteCount: bytes.count), kind: .pdf,
                     pageCount: 2, sha256: CoachDocumentSource.digest(bytes), importedAt: Date(timeIntervalSince1970: 1_790_000_000))
    }
    func testRegistersMetadataWithoutChangingOtherAppData() throws {
        var data = AppData(); let originalID = data.installationID, item = source()
        try CoachDocumentLibrary.register(item, data: &data)
        XCTAssertEqual(data.coachDocuments, [item]); XCTAssertEqual(data.installationID, originalID)
        XCTAssertNil(data.studyPDFs); XCTAssertEqual(StudyFiles.documents(in: data), [item.document])
    }
    func testSameHashUnderANewNameDoesNotCreateADuplicate() throws {
        var data = AppData(); let item = source(); try CoachDocumentLibrary.register(item, data: &data)
        var duplicate = item; duplicate.id = UUID(); duplicate.document.id = UUID(); duplicate.document.name = "Renamed QA.pdf"
        XCTAssertThrowsError(try CoachDocumentLibrary.register(duplicate, data: &data))
        XCTAssertEqual(data.coachDocuments, [item])
    }
    func testRepairPreservesLogicalRoutesReferencesAndImportDate() throws {
        var data = AppData(); let item = source(); try CoachDocumentLibrary.register(item, data: &data)
        let refs = [CoachDocumentReference(sourceID: item.id, pages: [2])]
        XCTAssertTrue(CoachDocumentLibrary.attach(refs, to: "synthetic-event", data: &data))
        var repaired = item; repaired.document.id = UUID()
        try CoachDocumentLibrary.register(repaired, replacing: item, data: &data)
        XCTAssertEqual(data.coachDocuments, [repaired]); XCTAssertEqual(data.coachDocumentEventLinks?.first?.references, refs)
        XCTAssertEqual(repaired.importedAt, item.importedAt)
        let route = try XCTUnwrap(CoachDocumentLibrary.url(sourceID: item.id, page: 2, sources: [repaired]))
        XCTAssertEqual(CoachDocumentLibrary.destination(route, sources: [repaired])?.source, repaired)
    }
    func testRepairRejectsStaleExpectedSourceWithoutChangingCurrentMetadata() throws {
        var data = AppData(); let item = source(); try CoachDocumentLibrary.register(item, data: &data)
        var repaired = item; repaired.document.id = UUID()
        var stale = item; stale.document.id = UUID()
        XCTAssertThrowsError(try CoachDocumentLibrary.register(repaired, replacing: stale, data: &data))
        XCTAssertEqual(data.coachDocuments, [item])
    }
    func testRepairCannotChangeContentNameKindOrLogicalIdentity() throws {
        var data = AppData(); let item = source(); try CoachDocumentLibrary.register(item, data: &data)
        var repaired = item; repaired.document.id = UUID()
        var variants = [CoachDocumentSource]()
        var next = repaired; next.sha256 = String(repeating: "a", count: 64); variants.append(next)
        next = repaired; next.document.name = "Other QA.pdf"; variants.append(next)
        next = repaired; next.kind = .photo; variants.append(next)
        next = repaired; next.id = UUID(); variants.append(next)
        for changed in variants {
            XCTAssertThrowsError(try CoachDocumentLibrary.register(changed, replacing: item, data: &data))
            XCTAssertEqual(data.coachDocuments, [item])
        }
    }
    func testExistingPhysicalIDCannotBeReusedByAnImport() throws {
        var data = AppData(); let item = source(); try CoachDocumentLibrary.register(item, data: &data)
        var other = source("OTHER.pdf"); other.document.id = item.document.id
        XCTAssertThrowsError(try CoachDocumentLibrary.register(other, data: &data))
        XCTAssertEqual(data.coachDocuments, [item])
    }
    func testImportCannotMutateAnEmbeddedBackupOrInconsistentLibrary() throws {
        var data = AppData(); data.studyPDFs = [:]
        XCTAssertThrowsError(try CoachDocumentLibrary.register(source(), data: &data))
        XCTAssertNil(data.coachDocuments)
        data.studyPDFs = nil; data.coachDocumentEventLinks = [.init(eventID: "qa", references: [.init(sourceID: UUID(), pages: [1])])]
        XCTAssertThrowsError(try CoachDocumentLibrary.register(source(), data: &data))
        XCTAssertNil(data.coachDocuments)
    }
    func testAggregateLibraryLimitLeavesRegisteredSourcesIntact() throws {
        var data = AppData()
        for index in 0..<5 {
            var item = source("QA-\(index).pdf"); item.document.byteCount = StudyFiles.maximumBytes
            try CoachDocumentLibrary.register(item, data: &data)
        }
        let before = data.coachDocuments
        XCTAssertThrowsError(try CoachDocumentLibrary.register(source("EXTRA.pdf"), data: &data))
        XCTAssertEqual(data.coachDocuments, before)
    }
}
