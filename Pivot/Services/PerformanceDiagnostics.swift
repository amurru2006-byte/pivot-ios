import Foundation
import Combine

// Only operation names, durations and counts; never calendar/chat/Health content.
@MainActor
final class PerformanceDiagnostics: ObservableObject {
    struct Entry: Identifiable {
        var id: String { name }
        var name: String
        var seconds: Double
        var count: Int
    }
    @Published private(set) var entries: [Entry] = []
    func record(_ name: String, seconds: Double) {
        if let index = entries.firstIndex(where: { $0.name == name }) {
            entries[index].seconds = seconds
            entries[index].count += 1
        } else { entries.append(.init(name: name, seconds: seconds, count: 1)) }
    }
}
