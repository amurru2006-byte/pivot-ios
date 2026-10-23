import Foundation

/// Key integrity only, not a replacement for JSONDecoder's grammar/types.
/// Check ORIGINAL bytes before a JSON parser can collapse duplicate fields.
enum CoachJSONIntegrity {
    private enum Frame { case object(Set<String>), array }
    static func hasUniqueObjectKeys(_ data: Data, maximumBytes: Int = 32_000) -> Bool {
        guard maximumBytes > 0, !data.isEmpty, data.count <= maximumBytes else { return false }
        let bytes = [UInt8](data), whitespace: Set<UInt8> = [9, 10, 13, 32]
        guard bytes.first(where: { !whitespace.contains($0) }) == 123 else { return false }
        var stack: [Frame] = [], index = 0
        while index < bytes.count {
            switch bytes[index] {
            case 34:
                let start = index
                index += 1
                while index < bytes.count {
                    if bytes[index] == 92 { index += 2; continue }
                    if bytes[index] == 34 { break }
                    index += 1
                }
                guard index < bytes.count else { return false }
                var next = index + 1
                while next < bytes.count, whitespace.contains(bytes[next]) { next += 1 }
                if next < bytes.count, bytes[next] == 58 {
                    guard let last = stack.last, case .object(var keys) = last,
                          let key = try? JSONDecoder().decode(String.self, from: Data(bytes[start...index])),
                          keys.insert(key).inserted else { return false }
                    stack[stack.count - 1] = .object(keys)
                }
            case 123: stack.append(.object([]))
            case 91: stack.append(.array)
            case 125:
                guard let last = stack.last, case .object = last else { return false }
                stack.removeLast()
            case 93:
                guard let last = stack.last, case .array = last else { return false }
                stack.removeLast()
            default: break
            }
            guard stack.count <= 32 else { return false }
            index += 1
        }
        return stack.isEmpty
    }
}
