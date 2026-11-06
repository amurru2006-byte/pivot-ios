import XCTest
import UIKit
import PDFKit

/// Runs in a standalone synthetic simulator test bundle, without launching the
/// user's Pivot installation, contacting a provider or opening real documents.
final class CoachDocumentReaderTests: XCTestCase {
    private func pdf(_ pages: [String]) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800)).pdfData { context in
            for text in pages {
                context.beginPage()
                (text as NSString).draw(in: CGRect(x: 40, y: 60, width: 520, height: 650),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.black])
            }
        }
    }
    func testRealPDFKeepsOnlyExplicitSelectedPages() throws {
        let prepared = try CoachDocumentReader.pdf(pdf(["FIRST PAGE QA", "SECOND PAGE QA", "THIRD PAGE QA"]), name: "QA.pdf")
        let pages = try CoachDocumentReader.pages(prepared.source, bytes: prepared.bytes, numbers: [2])
        XCTAssertEqual(prepared.source.pageCount, 3); XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages[0].number, 2); XCTAssertEqual(pages[0].reading, .text)
        XCTAssertTrue(pages[0].text.contains("SECOND PAGE QA"))
        XCTAssertFalse(pages[0].text.contains("FIRST PAGE QA"))
        XCTAssertTrue(prepared.source.matches(prepared.bytes))
    }
    func testMalformedPDFEnvelopeCannotPassPDFKitImport() {
        XCTAssertThrowsError(try CoachDocumentReader.pdf(Data("%PDF-1.4\nnot an actual PDF\n%%EOF".utf8), name: "QA.pdf"))
        XCTAssertThrowsError(try CoachDocumentReader.pdf(Data(), name: "QA.pdf"))
    }
    func testRepeatedUnknownAndEmptySelectionsAreRejected() throws {
        let value = try CoachDocumentReader.pdf(pdf(["QA"]), name: "QA.pdf")
        for selection in [[], [0], [2], [1, 1]] {
            XCTAssertThrowsError(try CoachDocumentReader.pages(value.source, bytes: value.bytes, numbers: selection))
        }
    }
    func testChangedBytesAndForgedPageCountAreRejectedBeforeReading() throws {
        let value = try CoachDocumentReader.pdf(pdf(["ORIGINAL QA"]), name: "QA.pdf")
        let other = pdf(["CHANGED QA"])
        XCTAssertThrowsError(try CoachDocumentReader.pages(value.source, bytes: other, numbers: [1]))
        var forged = value.source; forged.pageCount = 2
        XCTAssertThrowsError(try CoachDocumentReader.pages(forged, bytes: value.bytes, numbers: [1]))
    }
    func testBlankPageIsExplicitlyUnreadableInsteadOfInventingText() throws {
        let value = try CoachDocumentReader.pdf(pdf([""]), name: "QA.pdf")
        let pages = try CoachDocumentReader.pages(value.source, bytes: value.bytes, numbers: [1])
        XCTAssertEqual(pages.count, 1); XCTAssertEqual(pages[0].reading, .unreadable)
        XCTAssertEqual(pages[0].text, ""); XCTAssertNil(pages[0].ocrConfidence)
    }
    func testVisionCanReadAnExplicitRasterPhotoAndReportsOCRConfidence() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
            ("LABORATORY\nNOVEMBER 2026\n23:44" as NSString).draw(in: CGRect(x: 80, y: 100, width: 1000, height: 600),
                withAttributes: [.font: UIFont.systemFont(ofSize: 64), .foregroundColor: UIColor.black])
        }
        let value = try CoachDocumentReader.photo(try XCTUnwrap(image.jpegData(compressionQuality: 0.9)))
        XCTAssertEqual(value.source.kind, .photo); XCTAssertEqual(value.source.pageCount, 1)
        let pages = try CoachDocumentReader.pages(value.source, bytes: value.bytes, numbers: [1], forceOCR: true)
        XCTAssertEqual(pages[0].reading, .ocr); XCTAssertTrue(pages[0].text.contains("LABORATORY"))
        XCTAssertNotNil(pages[0].ocrConfidence); XCTAssertTrue(pages[0].isValid)
        // Recognition of this fixture does not prove arbitrary tables or dates.
    }
    func testImageSizeAndFormatLimitsAreEnforcedWithoutAProvider() {
        XCTAssertThrowsError(try CoachDocumentReader.photo(Data()))
        XCTAssertThrowsError(try CoachDocumentReader.photo(Data("not an image".utf8)))
        XCTAssertThrowsError(try CoachDocumentReader.photo(Data(repeating: 0, count: 20 * 1024 * 1024 + 1)))
    }
    func testBoundedFileImportKeepsPDFBytesAndRejectsOversizedFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("QA.pdf"), bytes = pdf(["LOCAL ONLY QA"])
        try bytes.write(to: url)
        XCTAssertEqual(try CoachDocumentReader.readFile(url).bytes, bytes)
        try Data(repeating: 0, count: StudyFiles.maximumBytes + 1).write(to: url)
        XCTAssertThrowsError(try CoachDocumentReader.readFile(url))
    }
}
