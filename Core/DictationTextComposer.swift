import Foundation

struct DictationTextComposer: Equatable {
    private(set) var prefix = ""
    private(set) var lastTranscript = ""
    private(set) var lastRenderedText = ""

    mutating func begin(currentText: String) {
        prefix = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        lastTranscript = ""
        lastRenderedText = currentText
    }

    mutating func apply(transcript rawTranscript: String, to currentText: String) -> String {
        let transcript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return currentText }
        let result: String
        if lastTranscript.isEmpty {
            result = currentText == lastRenderedText ? joined(prefix, transcript) : joined(currentText, transcript)
        } else if let range = currentText.range(of: lastTranscript, options: .backwards) {
            var value = currentText
            value.replaceSubrange(range, with: transcript)
            result = value
        } else if currentText == lastRenderedText {
            result = joined(prefix, transcript)
        } else {
            // If the user changed the recognized words while the microphone was
            // active, their edit wins. Add only genuinely new trailing words.
            let previousCount = lastTranscript.split(whereSeparator: { $0.isWhitespace }).count
            let words = transcript.split(whereSeparator: { $0.isWhitespace })
            let newTail = words.count > previousCount ? words.dropFirst(previousCount).joined(separator: " ") : ""
            result = newTail.isEmpty ? currentText : joined(currentText, newTail)
        }
        lastTranscript = transcript
        lastRenderedText = result
        return result
    }

    private func joined(_ left: String, _ right: String) -> String {
        let first = left.trimmingCharacters(in: .whitespacesAndNewlines)
        let second = right.trimmingCharacters(in: .whitespacesAndNewlines)
        if first.isEmpty { return second }
        if second.isEmpty { return first }
        return first + " " + second
    }
}
