import Foundation

struct CalendarRGB: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
}

enum ActivityTiming {
    static func seconds(start: Date, end: Date) -> Int? {
        let seconds = end.timeIntervalSince(start)
        guard seconds.isFinite, seconds >= 0, seconds <= 31 * 86400 else { return nil }
        return Int(seconds.rounded())
    }
    static func duration(_ seconds: Int) -> String {
        let value = max(0, seconds)
        if value % 60 != 0 { return "\(value / 3600) h \((value % 3600) / 60) min \(value % 60) s" }
        return "\(value / 3600) h \((value % 3600) / 60) min"
    }
}

struct SleepRecord: Codable {
    var bedtime: Date?
    var durationSeconds: Int?
    var score: Int?
    var quality: String = ""
    var awakenings: Int?
    var interruptionSeconds: Int?
}

enum CardioKind: String, Codable, CaseIterable {
    case walk, hike, treadmill
    var label: String {
        switch self {
        case .walk: return "Camminata"
        case .hike: return "Escursione"
        case .treadmill: return "Tapis roulant"
        }
    }
    static func suggested(_ title: String) -> CardioKind? {
        let text = title.lowercased()
        if text.contains("escursion") { return .hike }
        if text.contains("cammin") { return .walk }
        if text.contains("tapis") || text.contains("treadmill") { return .treadmill }
        return nil
    }
}

struct CardioRecord: Codable {
    var kind: CardioKind
    var durationSeconds: Int?
    var distanceKM: Double?
    var activeCalories: Double?
    var totalCalories: Double?
    var elevationM: Double?
    var paceSecondsPerKM: Int?
    var averageBPM: Int?
    var effort: Int?
    var speedKMH: Double?
    var inclinePercent: Double?
    var notes: String = ""
    var isValid: Bool {
        let doubles: [Double?] = [distanceKM, activeCalories, totalCalories, elevationM, speedKMH, inclinePercent]
        return doubles.allSatisfy { $0.map { $0.isFinite && $0 >= 0 && $0 <= 1_000_000 } ?? true }
            && (durationSeconds.map { (0...2678400).contains($0) } ?? true)
            && (paceSecondsPerKM.map { (0...86400).contains($0) } ?? true)
            && (averageBPM.map { (1...300).contains($0) } ?? true)
            && (effort.map { (1...10).contains($0) } ?? true)
    }
}
