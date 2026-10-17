import Foundation

/// The replacement map stays on-device, never in the request or model history.
struct CoachRewriteDraft {
    let original: String
    let message: String
    private let replacements: [String: String]

    init(original: String, events: [CalendarItem], data: AppData) {
        self.original = original
        var value = original, replacements: [String: String] = [:]
        let names = data.clients.flatMap { [$0.name] + ($0.calendarAliases ?? []) } + events.map(\.location)
        let escaped = Set(names.filter { $0.count >= 3 }).sorted { $0.count > $1.count }.map {
            "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: $0) + "(?![\\p{L}\\p{N}])"
        }
        let patterns = escaped + [
            #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#,
            #"\b(?:https?://|www\.)[^\s]+"#,
            #"\b[A-Z]{2}[0-9]{2}(?:\s?[A-Z0-9]){11,30}\b"#,
            #"(?<![\w\d])\+?(?!\d{4}-\d{2}-\d{2}\b)(?:\d[ .()\-]*){8,14}\d(?![\w\d])"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
                guard let range = Range(match.range, in: value) else { continue }
                let letters = UUID().uuidString.filter { $0 != "-" }.map { $0.isNumber ? Character(UnicodeScalar(97 + Int(String($0))!)!) : $0 }
                let marker = "<pv_" + String(letters).lowercased() + ">"
                replacements[marker] = String(value[range])
                value.replaceSubrange(range, with: marker)
            }
        }
        self.message = value; self.replacements = replacements
    }

    func restore(_ rewritten: String) throws -> String {
        guard !rewritten.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              rewritten.count <= 12_000 else { throw CoachV8Error.invalidResponse }
        func matches(_ pattern: String, in text: String) -> [String] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
                Range($0.range, in: text).map { String(text[$0]).lowercased() }
            }.sorted()
        }
        for pattern in [#"<pv_[a-z]+>"#, #"\d+(?:[.,:/-]\d+)*"#, #"\b(?:non|senza|mai|nessun\w*|niente)\b"#] {
            guard matches(pattern, in: message) == matches(pattern, in: rewritten) else { throw CoachV8Error.invalidResponse }
        }
        var value = rewritten
        for (marker, original) in replacements { value = value.replacingOccurrences(of: marker, with: original, options: .caseInsensitive) }
        return value
    }
}
