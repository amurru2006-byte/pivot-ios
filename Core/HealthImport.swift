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
    var isValid: Bool {
        !id.isEmpty && start.timeIntervalSince1970.isFinite && end.timeIntervalSince1970.isFinite
            && end > start && end.timeIntervalSince(start) <= 2_678_400 && (1...2_678_400).contains(durationSeconds)
            && [distanceKM, activeCalories, elevationM].allSatisfy { $0.map { $0.isFinite && (0...1_000_000).contains($0) } ?? true }
            && (averageBPM.map { (1...300).contains($0) } ?? true)
    }
    var pace: Int? {
        guard let km = distanceKM, km > 0 else { return nil }
        let value = Double(durationSeconds) / km
        return value.isFinite && (0...86400).contains(value) ? Int(value) : nil
    }
}

enum HealthWorkoutField: String, Codable, CaseIterable {
    case actualStart, actualEnd, activeMinutes, duration, distance, calories, heartRate, elevation, pace
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
            return overlap > 0 && overlap >= max(1, workout.end.timeIntervalSince(workout.start)) * 0.7
        }.sorted { $0.start < $1.start }
    }
    @discardableResult
    static func apply(_ summary: HealthWorkoutSummary, to event: CalendarItem, data: inout AppData, now: Date = Date()) -> Bool {
        guard summary.isValid else { return false }
        var record = data.records[event.id] ?? EventRecord(id: event.id, snapshot: event)
        let previous = record.health
        guard previous.map({ $0.id == summary.id }) ?? (record.status == .pending) else { return false }
        var managed = Set(previous == nil ? [] : (record.healthManagedFields ?? []))
        let originalManaged = record.healthManagedFields
        let firstImport = previous == nil
        let allowFields = firstImport || record.status == .completed
        // A field stops following Health permanently once it differs from the
        // last imported value, including explicit clearing. A later coincidence
        // with a new measurement must not silently reclaim that manual field.
        func merge<T: Equatable>(_ field: HealthWorkoutField, _ current: inout T?, old: T?, incoming: T?) {
            guard allowFields else { managed.remove(field); return }
            if firstImport {
                guard current == nil else { return }
                managed.insert(field); current = incoming
            } else if managed.contains(field) {
                guard current == old else { managed.remove(field); return }
                current = incoming
            }
        }
        let originalStart = record.actualStart, originalEnd = record.actualEnd, originalMinutes = record.activeMinutes
        let originalStatus = record.status
        let calendarSuggested = firstImport && record.timingFromCalendar == true && record.calendarTimingNeedsConfirmation != true
        if calendarSuggested {
            record.actualStart = nil; record.actualEnd = nil; record.activeMinutes = 0
        }
        // Explicit clock edits and calendar-synchronization requests are never
        // replaced by an observation, even if their numeric value coincides.
        if record.calendarTimingNeedsConfirmation == true || (firstImport && !calendarSuggested && (originalStart != nil || originalEnd != nil)) {
            managed.subtract([.actualStart, .actualEnd, .activeMinutes])
        } else {
            merge(.actualStart, &record.actualStart, old: previous?.start, incoming: summary.start)
            merge(.actualEnd, &record.actualEnd, old: previous?.end, incoming: summary.end)
            if firstImport {
                if (calendarSuggested || (originalStart == nil && originalEnd == nil)) && record.activeMinutes == 0 {
                    managed.insert(.activeMinutes); record.activeMinutes = summary.durationSeconds / 60
                }
            } else if managed.contains(.activeMinutes) {
                if allowFields && record.activeMinutes == previous.map({ $0.durationSeconds / 60 }) {
                    record.activeMinutes = summary.durationSeconds / 60
                } else { managed.remove(.activeMinutes) }
            }
        }
        if let start = record.actualStart, let end = record.actualEnd, end <= start {
            record.actualStart = originalStart; record.actualEnd = originalEnd
            managed.subtract([.actualStart, .actualEnd, .activeMinutes])
            record.activeMinutes = originalMinutes
        }
        record.health = summary
        if firstImport { record.status = .completed }
        if managed.contains(.actualStart) && managed.contains(.actualEnd) { record.timingFromCalendar = false }
        if let kind = CardioKind.suggested(event.title) {
            // Removing the cardio record or changing its type is a manual edit.
            if (firstImport && record.cardio == nil) || record.cardio?.kind == kind {
                var cardio = record.cardio ?? CardioRecord(kind: kind)
                merge(.duration, &cardio.durationSeconds, old: previous?.durationSeconds, incoming: summary.durationSeconds)
                merge(.distance, &cardio.distanceKM, old: previous?.distanceKM, incoming: summary.distanceKM)
                merge(.calories, &cardio.activeCalories, old: previous?.activeCalories, incoming: summary.activeCalories)
                merge(.heartRate, &cardio.averageBPM, old: previous?.averageBPM, incoming: summary.averageBPM)
                merge(.elevation, &cardio.elevationM, old: previous?.elevationM, incoming: summary.elevationM)
                if managed.contains(.duration) && managed.contains(.distance) {
                    merge(.pace, &cardio.paceSecondsPerKM, old: previous?.pace, incoming: summary.pace)
                } else { managed.remove(.pace) }
                record.cardio = cardio
            } else { managed.subtract([.duration, .distance, .calories, .heartRate, .elevation, .pace]) }
        }
        record.healthManagedFields = HealthWorkoutField.allCases.filter { managed.contains($0) }
        let changed = previous != summary || originalManaged != record.healthManagedFields
            || originalStart != record.actualStart || originalEnd != record.actualEnd
            || originalMinutes != record.activeMinutes || originalStatus != record.status
        guard changed else { return false }
        record.updatedAt = now
        if firstImport { record.snapshot = event }
        data.records[event.id] = record
        return true
    }
    // Default exports exclude automatically imported health values. Explicit user consent can include them.
    static func exportData(_ data: AppData, allowHealth: Bool? = nil) -> AppData {
        guard !(allowHealth ?? (data.settings.includeHealthInExports == true)) else { return data }
        var result = data
        // Provenance itself reveals a Health import, even if a caller has
        // removed the associated summary. Strip it from every exported copy.
        for id in Array(result.records.keys) { result.records[id]?.healthManagedFields = nil }
        for id in Array((result.activityDrafts ?? [:]).keys) { result.activityDrafts?[id]?.record.healthManagedFields = nil }
        // Legacy profiles have no reliable per-field provenance. Exclude the
        // entire copy rather than misclassifying imported measurements as manual.
        result.strengthProfile = nil
        result.training?.achievements?.removeAll { $0.kind == .rank }
        result.workoutReviews = nil
        result.coach?.messages.removeAll { $0.healthDerived == true }
        if result.actualWorkoutDraft?.health != nil || result.actualWorkoutDraft?.healthDerived == true { result.actualWorkoutDraft = nil }
        let derivedIDs = Set(result.moves.filter { $0.healthDerived == true }.map { $0.source.id })
        result.moves.removeAll { $0.healthDerived == true }
        result.coach?.pendingCalendarChanges.removeAll { $0.move.healthDerived == true }
        result.coach?.options.removeAll { $0.moves.contains { $0.healthDerived == true } }
        for id in derivedIDs {
            result.records[id]?.actualStart = nil; result.records[id]?.actualEnd = nil; result.records[id]?.activeMinutes = 0
            result.records[id]?.status = .pending
        }
        for key in Array(result.checkIns.keys) {
            if result.checkIns[key]?.sleep?.importedFromHealth == true { result.checkIns[key]?.sleep = nil }
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
            // Old records cannot distinguish a manual outcome from an imported
            // one. Neutralize only the exported copy, never the stored history.
            result.records[id]?.status = .pending
        }
        for id in Array(result.records.keys) where result.records[id]?.healthSleep != nil {
            result.records[id]?.healthSleep = nil; result.records[id]?.actualStart = nil; result.records[id]?.actualEnd = nil; result.records[id]?.activeMinutes = 0
            result.records[id]?.status = .pending
        }
        for id in Array((result.activityDrafts ?? [:]).keys) {
            guard var draft = result.activityDrafts?[id] else { continue }
            if draft.record.health != nil || draft.record.healthSleep != nil {
                draft.record.health = nil; draft.record.healthSleep = nil; draft.record.cardio = nil
                draft.record.actualStart = nil; draft.record.actualEnd = nil; draft.record.activeMinutes = 0
                draft.record.status = .pending
                result.activityDrafts?[id] = draft
            }
        }
        return result
    }
}
