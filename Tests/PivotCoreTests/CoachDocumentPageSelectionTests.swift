import XCTest
@testable import PivotCore

final class CoachDocumentPageSelectionTests: XCTestCase {
    func testExplicitPagesAndRangesAreSortedWithoutIncludingOtherPages() {
        XCTAssertEqual(CoachDocumentPageSelection.parse("7, 2-4, 1", pageCount: 8), [1, 2, 3, 4, 7])
    }
    func testOverlapAndDuplicatesRequireCorrectionInsteadOfSilentMerging() {
        for value in ["1,1", "1-3,3-4", "4-2"] { XCTAssertNil(CoachDocumentPageSelection.parse(value, pageCount: 10)) }
    }
    func testMissingOutOfBoundsAndMalformedPagesAreRejected() {
        for value in ["", "0", "11", "1,", ",1", "-1", "1--2", "1.5", "1;2", "01", "1–3", "١"] {
            XCTAssertNil(CoachDocumentPageSelection.parse(value, pageCount: 10), value)
        }
    }
    func testFortyPagesIsAnExplicitLimitNotATruncation() {
        XCTAssertEqual(CoachDocumentPageSelection.parse("1-40", pageCount: 500)?.count, 40)
        XCTAssertNil(CoachDocumentPageSelection.parse("1-41", pageCount: 500))
        XCTAssertNil(CoachDocumentPageSelection.parse("1-40,42", pageCount: 500))
    }
    func testInvalidSourcePageCountsNeverProduceASelection() {
        for count in [0, -1, 501] { XCTAssertNil(CoachDocumentPageSelection.parse("1", pageCount: count)) }
    }
    func testUnboundedOrOverflowingInputIsRejected() {
        XCTAssertNil(CoachDocumentPageSelection.parse(String(repeating: "1", count: 301), pageCount: 500))
        XCTAssertNil(CoachDocumentPageSelection.parse("9999999999999999999999999999999999", pageCount: 500))
    }
}
