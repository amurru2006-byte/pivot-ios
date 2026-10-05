import Foundation

struct HealthInterval: Equatable {
    var start: Date
    var end: Date
}

struct HealthWorkoutSummary: Codable, Identifiable, Equatable {
    var id: String
    var start: Date
    var end: Date
    var type: String
    var durationSeconds: Int
    var distanceKM: Double?
    var activeCalories: Double?
    var averageBPM: Int?
    var elevationM: Double?
}

struct HealthSleepSummary: Equatable {
    var start: Date
    var end: Date
    var durationSeconds: Int
    var interruptionSeconds: Int?
    var awakenings: Int?
}

enum HealthImport {
    // Apple Watch and iPhone can both contribute overlapping samples. Count their union.
    static func merged(_ intervals: [HealthInterval]) -> [HealthInterval] {
        var result: [HealthInterval] = []
        for item in intervals.filter({ $0.end > $0.start }).sorted(by: { $0.start < $1.start }) {
            if let last = result.last, item.start <= last.end {
                result[result.count - 1].end = max(last.end, item.end)
            } else { result.append(item) }
        }
        return result
    }
    static func sleep(asleep: [HealthInterval], awake: [HealthInterval], endingOn day: Date) -> HealthSleepSummary? {
        let intervals = merged(asleep)
        // Cluster a main overnight sleep; don't add every nap to the same night.
        var groups: [[HealthInterval]] = []
        for interval in intervals {
            if let last = groups.last?.last, interval.start.timeIntervalSince(last.end) <= 90 * 60 {
                groups[groups.count - 1].append(interval)
            } else { groups.append([interval]) }
        }
        let candidates = groups.filter { $0.last.map { PivotDate.calendar.isDate($0.end, inSameDayAs: day) } ?? false }
        guard let group = candidates.max(by: { seconds($0) < seconds($1) }), let first = group.first, let last = group.last else { return nil }
        let interruptions = merged(awake).compactMap { value -> HealthInterval? in
            let start = max(first.start, value.start), end = min(last.end, value.end)
            return end > start ? .init(start: start, end: end) : nil
        }
        let overlapAwake = interruptions.reduce(0.0) { result, value in
            result + group.reduce(0.0) { sum, asleep in
                sum + max(0, min(asleep.end, value.end).timeIntervalSince(max(asleep.start, value.start)))
            }
        }
        return .init(start: first.start, end: last.end, durationSeconds: max(0, seconds(group) - Int(overlapAwake.rounded())),
                     interruptionSeconds: interruptions.isEmpty ? nil : seconds(interruptions),
                     awakenings: interruptions.isEmpty ? nil : interruptions.count)
    }
    private static func seconds(_ items: [HealthInterval]) -> Int {
        Int(items.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }.rounded())
    }
    static func candidates(_ workout: HealthWorkoutSummary, events: [CalendarItem]) -> [CalendarItem] {
        events.filter { event in
            guard event.kind == .workout, !event.isAllDay else { return false }
            let requested = CardioKind.suggested(event.title)
            let correctType: Bool
            if let requested { correctType = workout.type == requested.rawValue || (requested == .treadmill && workout.type == "walk") }
            else { correctType = ["strength", "functional", "other"].contains(workout.type) }
            guard correctType else { return false }
            let overlap = min(event.end, workout.end).timeIntervalSince(max(event.start, workout.start))
            // A station-university walk outside the workout slot is never a scheduled workout.
            return overlap > 0 && overlap >= Double(max(1, workout.durationSeconds)) * 0.7
        }.sorted { $0.start < $1.start }
    }
    static func apply(_ summary: HealthWorkoutSummary, to event: CalendarItem, data: inout AppData) {
        var record = data.records[event.id] ?? EventRecord(id: event.id, snapshot: event)
        // Don't overwrite an explicit skip, partial outcome or manually corrected timer.
        guard record.status == .pending || record.health?.id == summary.id else { return }
        record.health = summary
        if record.status == .pending {
            record.actualStart = summary.start; record.actualEnd = summary.end
            record.activeMinutes = summary.durationSeconds / 60; record.status = .completed
        }
        if let kind = CardioKind.suggested(event.title) {
            var cardio = record.cardio ?? CardioRecord(kind: kind)
            cardio.durationSeconds = summary.durationSeconds; cardio.distanceKM = summary.distanceKM
            cardio.activeCalories = summary.activeCalories; cardio.averageBPM = summary.averageBPM; cardio.elevationM = summary.elevationM
            if let km = summary.distanceKM, km > 0 { cardio.paceSecondsPerKM = Int(Double(summary.durationSeconds) / km) }
            record.cardio = cardio
        }
        record.updatedAt = Date(); record.snapshot = event; data.records[event.id] = record
    }
    // Default exports exclude automatically imported health values. Explicit user consent can include them.
    static func exportData(_ data: AppData) -> AppData {
        guard data.settings.includeHealthInExports != true else { return data }
        var result = data
        for key in Array(result.checkIns.keys) where result.checkIns[key]?.sleep?.importedFromHealth == true {
            result.checkIns[key]?.sleep = nil
            if result.checkIns[key]?.healthWakeTime == result.checkIns[key]?.wakeTime { result.checkIns[key]?.wakeTime = nil }
            result.checkIns[key]?.healthWakeTime = nil
        }
        for id in Array(result.records.keys) where result.records[id]?.health != nil {
            if let summary = result.records[id]?.health {
                if result.records[id]?.actualStart == summary.start { result.records[id]?.actualStart = nil }
                if result.records[id]?.actualEnd == summary.end { result.records[id]?.actualEnd = nil }
                if result.records[id]?.activeMinutes == summary.durationSeconds / 60 { result.records[id]?.activeMinutes = 0 }
            }
            result.records[id]?.health = nil
            result.records[id]?.cardio = nil
        }
        for id in Array(result.records.keys) where result.records[id]?.healthSleep != nil {
            result.records[id]?.healthSleep = nil; result.records[id]?.actualStart = nil; result.records[id]?.actualEnd = nil; result.records[id]?.activeMinutes = 0
        }
        for id in Array((result.activityDrafts ?? [:]).keys) {
            guard var draft = result.activityDrafts?[id] else { continue }
            if draft.record.health != nil || draft.record.healthSleep != nil {
                draft.record.health = nil; draft.record.healthSleep = nil; draft.record.cardio = nil
                draft.record.actualStart = nil; draft.record.actualEnd = nil; draft.record.activeMinutes = 0
                result.activityDrafts?[id] = draft
            }
        }
        return result
    }
}
