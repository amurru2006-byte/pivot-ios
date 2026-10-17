import Foundation

/// Recognition hypotheses may restart after a pause without `isFinal`.
/// Keep completed utterances separate from the hypothesis that can still change.
struct SpeechTranscriptBuffer: Equatable {
    private(set) var completed = ""
    private(set) var hypothesis = ""
    private var boundaryReported = false
    private var previousEnd: TimeInterval?

    var text: String { Self.join(completed, hypothesis) }

    mutating func update(_ raw: String, start: TimeInterval?, end: TimeInterval?,
                         utteranceFinished: Bool) -> String {
        let next = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !next.isEmpty else { return text }
        let oldWords = Self.words(hypothesis), newWords = Self.words(next)
        let cumulative = !oldWords.isEmpty && newWords.starts(with: oldWords)
        let sameWords = !oldWords.isEmpty && oldWords == newWords
        let laterAudio = start.flatMap { first in previousEnd.map { first > $0 + 0.05 } } ?? false
        if !hypothesis.isEmpty && !cumulative && !sameWords && (boundaryReported || laterAudio) {
            finishSegment()
        }
        hypothesis = next
        // Repeated final-like callbacks must not append the same utterance twice.
        boundaryReported = utteranceFinished || (sameWords && boundaryReported)
        if let end, end.isFinite, end >= 0 { previousEnd = end }
        return text
    }

    mutating func finishSegment() {
        completed = Self.join(completed, hypothesis)
        hypothesis = ""; boundaryReported = false; previousEnd = nil
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: .alphanumerics.inverted).filter { !$0.isEmpty }
    }

    private static func join(_ left: String, _ right: String) -> String {
        if left.isEmpty { return right }
        if right.isEmpty { return left }
        return left + " " + right
    }
}
