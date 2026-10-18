import Foundation

enum TrainingDurationTimeBand: String, Codable {
    case morning, afternoon, evening
    static func at(_ date: Date) -> Self {
        let hour = PivotDate.calendar.component(.hour, from: date)
        return hour < 12 ? .morning : hour < 18 ? .afternoon : .evening
    }
    var label: String {
        switch self { case .morning: return "mattina"; case .afternoon: return "pomeriggio"; case .evening: return "sera" }
    }
}

/// Descriptive sample statistics. The interquartile interval is NOT a confidence
/// interval, an 80% promise, or a prediction of physiological readiness.
struct DurationStatistics: Equatable {
    var count: Int
    var medianMinutes: Int
    var lowerMinutes: Int
    var upperMinutes: Int
    var minimumMinutes: Int
    var maximumMinutes: Int

    static func make(_ values: [Double]) -> Self? {
        guard (3...1000).contains(values.count), values.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 1440 }) else { return nil }
        let sorted = values.sorted()
        func quantile(_ fraction: Double) -> Double {
            let position = Double(sorted.count - 1) * fraction
            let lower = Int(floor(position)), upper = Int(ceil(position))
            return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
        }
        return .init(count: sorted.count, medianMinutes: Int(ceil(quantile(0.5))),
                     lowerMinutes: max(1, Int(floor(quantile(0.25)))), upperMinutes: Int(ceil(quantile(0.75))),
                     minimumMinutes: max(1, Int(floor(sorted[0]))), maximumMinutes: Int(ceil(sorted[sorted.count - 1])))
    }
}
