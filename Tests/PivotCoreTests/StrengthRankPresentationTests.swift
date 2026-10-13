import XCTest
@testable import PivotCore

final class StrengthRankPresentationTests: XCTestCase {
    func testAllSevenOriginalNamesAreInOrder() {
        XCTAssertEqual(StrengthRankPresentation.names, ["Schiavo della gravità", "Patto col ferro", "Sfidante della fisica",
                                                       "Distruttore di ego", "Mutante", "Forza primordiale", "Onnipotente del carico"])
        XCTAssertEqual(StrengthRankPresentation.count, 7)
        for level in 0..<7 { XCTAssertEqual(StrengthRankPresentation.name(level), StrengthRankPresentation.names[level]) }
    }
    func testEveryLevelHasAnOriginalEmblemAndTitleAsset() {
        for level in 0..<7 {
            XCTAssertEqual(StrengthRankPresentation.emblem(level), "Rank\(level + 1)Emblem")
            XCTAssertEqual(StrengthRankPresentation.titleArtwork(level), "Rank\(level + 1)Title")
        }
    }
    func testInvalidLevelsDoNotInventNamesOrAssets() {
        for level in [-1, 7, Int.min, Int.max] {
            XCTAssertEqual(StrengthRankPresentation.name(level), "Rank non disponibile")
            XCTAssertNil(StrengthRankPresentation.emblem(level)); XCTAssertNil(StrengthRankPresentation.titleArtwork(level))
        }
    }
    func testArtworkDoesNotChangeTheSevenMotivationalThresholds() {
        XCTAssertEqual(StrengthRanking.percentileFloors, [0, 10, 30, 50, 70, 80, 90])
        XCTAssertEqual(StrengthRanking.percentileFloors.count, StrengthRankPresentation.count)
    }
}
