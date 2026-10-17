import XCTest
@testable import PivotCore

final class SpeechTranscriptBufferTests: XCTestCase {
    func testPartialCorrectionsReplaceOnlyCurrentUtterance() {
        var buffer = SpeechTranscriptBuffer()
        XCTAssertEqual(buffer.update("Voglio fare", start: 0, end: 1, utteranceFinished: false), "Voglio fare")
        XCTAssertEqual(buffer.update("Vorrei fare la spesa.", start: 0, end: 2, utteranceFinished: false), "Vorrei fare la spesa.")
    }

    func testPauseBoundaryWithoutIsFinalPreservesPreviousWords() {
        var buffer = SpeechTranscriptBuffer()
        _ = buffer.update("Domani devo studiare.", start: 0, end: 3, utteranceFinished: true)
        XCTAssertEqual(buffer.update("Poi fare la spesa.", start: 0, end: 2, utteranceFinished: false),
                       "Domani devo studiare. Poi fare la spesa.")
        XCTAssertEqual(buffer.update("Poi fare la spesa e cucinare.", start: 0, end: 4, utteranceFinished: true),
                       "Domani devo studiare. Poi fare la spesa e cucinare.")
    }

    func testNewAudioRangePreservesWordsWithoutBoundaryMetadata() {
        var buffer = SpeechTranscriptBuffer()
        _ = buffer.update("Prima lo studio.", start: 1, end: 3, utteranceFinished: false)
        XCTAssertEqual(buffer.update("Dopo la palestra.", start: 6, end: 8, utteranceFinished: false),
                       "Prima lo studio. Dopo la palestra.")
    }

    func testRepeatedBoundaryAndPunctuationDoNotDuplicateText() {
        var buffer = SpeechTranscriptBuffer()
        _ = buffer.update("Latte e uova", start: 0, end: 2, utteranceFinished: true)
        XCTAssertEqual(buffer.update("Latte e uova.", start: 0, end: 2, utteranceFinished: true), "Latte e uova.")
        XCTAssertEqual(buffer.update("Latte e uova.", start: 0, end: 2, utteranceFinished: true), "Latte e uova.")
        buffer.finishSegment()
        XCTAssertEqual(buffer.update("Anche farina.", start: 0, end: 1, utteranceFinished: false), "Latte e uova. Anche farina.")
    }

    func testCumulativeResultsAfterBoundaryDoNotDuplicatePrefix() {
        var buffer = SpeechTranscriptBuffer()
        _ = buffer.update("Prima studio.", start: 0, end: 1, utteranceFinished: true)
        XCTAssertEqual(buffer.update("Prima studio. Poi cucino.", start: 0, end: 4, utteranceFinished: true), "Prima studio. Poi cucino.")
        XCTAssertEqual(buffer.update("Infine riposo.", start: 0, end: 1, utteranceFinished: false), "Prima studio. Poi cucino. Infine riposo.")
    }

    func testEmptyCallbacksAndComposerPreserveLongSpeech() {
        var buffer = SpeechTranscriptBuffer(), composer = DictationTextComposer()
        composer.begin(currentText: "Appunti:")
        var displayed = "Appunti:"
        for index in 0..<150 {
            let text = buffer.update("Attività numero \(index).", start: 0, end: 1, utteranceFinished: true)
            displayed = composer.apply(transcript: text, to: displayed)
            XCTAssertEqual(buffer.update("", start: nil, end: nil, utteranceFinished: false), text)
        }
        XCTAssertTrue(displayed.hasPrefix("Appunti: Attività numero 0."))
        XCTAssertTrue(displayed.hasSuffix("Attività numero 149."))
        XCTAssertEqual(displayed.components(separatedBy: "Attività numero").count - 1, 150)
    }

    func testPermissionIsExplicitAndExpiresOnAnotherDayOrRevocation() {
        var permission = CoachConversationPermission()
        XCTAssertFalse(permission.allows(dayKey: "2026-01-10"))
        permission.authorize(dayKey: "2026-01-10")
        XCTAssertTrue(permission.allows(dayKey: "2026-01-10"))
        XCTAssertFalse(permission.allows(dayKey: "2026-01-11"))
        permission.revoke()
        XCTAssertFalse(permission.allows(dayKey: "2026-01-10"))
    }
}
