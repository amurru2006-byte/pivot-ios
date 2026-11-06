import Foundation

enum CoachDocumentPageSelection {
    /// Explicit civil page numbers only; no silent truncation, overlap or
    /// interpretation of a locale-dependent range. Commas and ASCII '-' only.
    static func parse(_ text: String, pageCount: Int) -> [Int]? {
        guard (1...500).contains(pageCount), !text.isEmpty, text.utf16.count <= 300 else { return nil }
        let pieces = text.split(separator: ",", omittingEmptySubsequences: false)
        guard (1...40).contains(pieces.count) else { return nil }
        var result = [Int]()
        func number(_ value: Substring) -> Int? {
            let value = value.trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(value), value == String(number), (1...pageCount).contains(number) else { return nil }
            return number
        }
        for piece in pieces {
            let bounds = piece.split(separator: "-", omittingEmptySubsequences: false)
            guard (1...2).contains(bounds.count), let first = number(bounds[0]),
                  let last = number(bounds.last!), last >= first,
                  result.count + last - first + 1 <= 40 else { return nil }
            for page in first...last {
                guard !result.contains(page) else { return nil }
                result.append(page)
            }
        }
        return result.sorted()
    }
}
