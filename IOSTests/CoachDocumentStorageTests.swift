import XCTest
import UIKit

/// Temporary synthetic PDFs only. No Pivot app, account or real library.
final class CoachDocumentStorageTests: XCTestCase {
    private func prepared(_ text: String = "SYNTHETIC STORAGE QA") throws -> CoachDocumentReader.Prepared {
        let bytes = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 500, height: 700)).pdfData { context in
            context.beginPage()
            (text as NSString).draw(at: CGPoint(x: 30, y: 50), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
        }
        return try CoachDocumentReader.pdf(bytes, name: "QA.pdf")
    }
    private func folder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    func testNewPDFRoundTripsWithVerifiedBytes() throws {
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let item = try prepared()
        try CoachDocumentStorage.writeNew(item.source, bytes: item.bytes, directory: directory)
        XCTAssertEqual(try CoachDocumentStorage.verifiedBytes(item.source, directory: directory), item.bytes)
    }
    func testExistingFileCannotBeOverwrittenEvenWithMatchingBytes() throws {
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let item = try prepared(); try CoachDocumentStorage.writeNew(item.source, bytes: item.bytes, directory: directory)
        XCTAssertThrowsError(try CoachDocumentStorage.writeNew(item.source, bytes: item.bytes, directory: directory))
        XCTAssertEqual(try CoachDocumentStorage.verifiedBytes(item.source, directory: directory), item.bytes)
    }
    func testForeignExistingFileIsLeftUntouched() throws {
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let item = try prepared(), url = StudyFiles.url(for: item.source.document.id, directory: directory)
        let foreign = Data("DO NOT OVERWRITE QA".utf8); try foreign.write(to: url)
        XCTAssertThrowsError(try CoachDocumentStorage.writeNew(item.source, bytes: item.bytes, directory: directory))
        XCTAssertEqual(try Data(contentsOf: url), foreign)
    }
    func testChangedSourceHashFailsBeforeCreatingAFile() throws {
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        var item = try prepared(); item.source.sha256 = String(repeating: "a", count: 64)
        XCTAssertThrowsError(try CoachDocumentStorage.writeNew(item.source, bytes: item.bytes, directory: directory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
    func testForgedPDFPageCountFailsBeforeCreatingAFile() throws {
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        var item = try prepared(); item.source.pageCount = 2
        XCTAssertThrowsError(try CoachDocumentStorage.writeNew(item.source, bytes: item.bytes, directory: directory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
    func testMissingPDFIsReportedWithoutInventingAReplacement() throws {
        let directory = folder(), item = try prepared()
        XCTAssertThrowsError(try CoachDocumentStorage.verifiedBytes(item.source, directory: directory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
    func testChangedPDFCannotBeReturnedForPreview() throws {
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let item = try prepared(); try CoachDocumentStorage.writeNew(item.source, bytes: item.bytes, directory: directory)
        let replacement = try prepared("DIFFERENT QA")
        try replacement.bytes.write(to: StudyFiles.url(for: item.source.document.id, directory: directory))
        XCTAssertThrowsError(try CoachDocumentStorage.verifiedBytes(item.source, directory: directory))
    }
    func testRepairToNewPhysicalIDPreservesThePreviousSnapshotFile() throws {
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let item = try prepared(); try CoachDocumentStorage.writeNew(item.source, bytes: item.bytes, directory: directory)
        var repaired = item.source; repaired.document.id = UUID()
        try CoachDocumentStorage.writeNew(repaired, bytes: item.bytes, directory: directory)
        XCTAssertEqual(try CoachDocumentStorage.verifiedBytes(item.source, directory: directory), item.bytes)
        XCTAssertEqual(try CoachDocumentStorage.verifiedBytes(repaired, directory: directory), item.bytes)
        XCTAssertEqual(repaired.id, item.source.id)
    }
}
