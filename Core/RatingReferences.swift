import Foundation

enum RatingMetric: String, CaseIterable, Identifiable {
    case energy, fatigue, mood, hungerBefore, hungerAfter
    var id: String { rawValue }
    var label: String {
        switch self {
        case .energy: return "Energia"
        case .fatigue: return "Stanchezza"
        case .mood: return "Umore"
        case .hungerBefore: return "Fame prima"
        case .hungerAfter: return "Fame dopo"
        }
    }
    func target(in settings: Settings) -> Int? {
        let value = settings.ratingTargets?[rawValue] ?? (self == .energy ? 7 : -1)
        return (0...10).contains(value) ? value : nil
    }
}

struct WeeklyRatingReference: Equatable {
    var mean: Double?
    var weeksWithData: Int
    var samples: Int
}

enum RatingReferences {
    static func week(containing date: Date) -> DateInterval {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = PivotDate.calendar.timeZone
        return calendar.dateInterval(of: .weekOfYear, for: date)!
    }
    /// Four completed ISO weeks preceding the selected event/check-in week.
    /// Each week's mean has equal weight; missing weeks and nil answers are omitted.
    static func historical(_ metric: RatingMetric, before date: Date, data: AppData) -> WeeklyRatingReference {
        let to = week(containing: date).start
        let from = PivotDate.calendar.date(byAdding: .day, value: -28, to: to)!
        var groups: [Date: [Double]] = [:]
        func add(_ value: Int?, on date: Date) {
            guard let value, (0...10).contains(value), date >= from, date < to else { return }
            groups[week(containing: date).start, default: []].append(Double(value))
        }
        for record in data.records.values where [.completed, .partial].contains(record.status) {
            let date = record.actualStart ?? record.snapshot.start
            switch metric {
            case .energy: add(record.energy, on: date)
            case .fatigue: add(record.fatigue, on: date)
            case .hungerBefore: add(record.hungerBefore, on: date)
            case .hungerAfter: add(record.hungerAfter, on: date)
            case .mood: break
            }
        }
        for check in data.checkIns.values {
            let parts = check.id.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3, let date = PivotDate.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { continue }
            switch metric {
            case .energy: add(check.energyMorning, on: date); add(check.energyEvening, on: date)
            case .fatigue: add(check.fatigueMorning, on: date); add(check.fatigueEvening, on: date)
            case .mood: add(check.moodMorning, on: date); add(check.moodEvening, on: date)
            case .hungerBefore, .hungerAfter: break
            }
        }
        let means = groups.values.map { $0.reduce(0, +) / Double($0.count) }
        return .init(mean: means.isEmpty ? nil : means.reduce(0, +) / Double(means.count), weeksWithData: means.count, samples: groups.values.reduce(0) { $0 + $1.count })
    }
}
