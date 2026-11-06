import XCTest

/// Bounded temporary UTF-8 files only; JSON semantics are checked separately by
/// the request-bound Core decoder. No real documents, pasteboard or network.
final class CoachDocumentReplyFileTests: XCTestCase {
    private func folder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    func testReplyReaderPreservesExactUTF8WithoutParsingOrExecutingIt() throws {
        let directory = folder(); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data("{\"questions\":[\"Qual è l’anno?\"]}".utf8), url = directory.appendingPathComponent("reply-qa.json")
        try bytes.write(to: url)
        XCTAssertEqual(try CoachDocumentReplyFile.read(url), bytes)
    }
    func testExactly64000BytesCanBeReadButNextByteFailsInsteadOfTruncation() throws {
        let directory = folder(); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("reply-qa.txt"), bytes = Data(repeating: 32, count: 64_000)
        try bytes.write(to: url); XCTAssertEqual(try CoachDocumentReplyFile.read(url), bytes)
        try Data(repeating: 32, count: 64_001).write(to: url)
        XCTAssertThrowsError(try CoachDocumentReplyFile.read(url))
        XCTAssertEqual(try Data(contentsOf: url).count, 64_001)
    }
    func testMissingEmptyAndInvalidUTF8RepliesAreRejectedWithoutReplacingFile() throws {
        let directory = folder(); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("reply-qa.json")
        XCTAssertThrowsError(try CoachDocumentReplyFile.read(url))
        try Data().write(to: url); XCTAssertThrowsError(try CoachDocumentReplyFile.read(url))
        let invalid = Data([0xff, 0xfe, 0xfd]); try invalid.write(to: url)
        XCTAssertThrowsError(try CoachDocumentReplyFile.read(url))
        XCTAssertEqual(try Data(contentsOf: url), invalid)
    }
    func testRemoteURLIsRejectedWithoutStartingANetworkRequest() throws {
        XCTAssertThrowsError(try CoachDocumentReplyFile.read(try XCTUnwrap(URL(string: "https://example.invalid/reply.json"))))
    }
}
