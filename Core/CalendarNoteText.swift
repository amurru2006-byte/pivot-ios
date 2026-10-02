import Foundation

// Calendar notes need readable text, not a WebKit document importer. Never loads URLs.
enum CalendarNoteText {
    private static func replace(_ text: String, _ pattern: String, _ replacement: String) -> String {
        text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }
    static func plain(_ value: String) -> String {
        guard value.contains("<") || value.contains("&") else { return value }
        var text = replace(value, "(?is)<(script|style)\\b[^>]*>.*?</\\1\\s*>", "")
        text = replace(text, "(?s)<!--.*?-->", "")
        text = replace(text, "(?i)<br\\s*/?>|</(?:p|div|li|h[1-6]|ul|ol|tr|section)\\s*>", "\n")
        text = replace(text, "(?i)<li(?:\\s[^<>]*)?>", "• ")
        text = replace(text, "</?[a-zA-Z][a-zA-Z0-9:-]*(?:\\s[^<>]*)?\\s*/?>", "")
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "ndash": "–", "mdash": "—", "hellip": "…", "bull": "•", "euro": "€", "agrave": "à", "egrave": "è", "eacute": "é", "igrave": "ì", "ograve": "ò", "ugrave": "ù"]
        let regex = try! NSRegularExpression(pattern: "&(#(?:[xX][0-9a-fA-F]+|[0-9]+)|[a-zA-Z]+);")
        // Two passes also handle notes escaped once by a calendar export.
        for _ in 0..<2 {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches.reversed() {
                guard let whole = Range(match.range, in: text), let keyRange = Range(match.range(at: 1), in: text) else { continue }
                let key = String(text[keyRange])
                var decoded = named[key]
                if key.hasPrefix("#") {
                    let hex = key.dropFirst().hasPrefix("x") || key.dropFirst().hasPrefix("X")
                    if let number = UInt32(key.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10), let scalar = UnicodeScalar(number) { decoded = String(scalar) }
                }
                if let decoded { text.replaceSubrange(whole, with: decoded) }
            }
        }
        return replace(text, "\n[ \\t]*\n(?:[ \\t]*\n)+", "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
