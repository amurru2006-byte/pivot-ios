import Foundation

struct RecoverySuggestion: Identifiable {
    var id: String { String(start.timeIntervalSince1970) }
    var start: Date
    var end: Date
    var explanation: String
}

enum Planner {
    // No silent displacement or compression: every other timed event blocks its own slot.
    // Buffers are user-confirmed durations, not invented routing estimates.
    static func recover(_ target: CalendarItem, events: [CalendarItem], data: AppData, now: Date, days: Int = 3) -> [RecoverySuggestion] {
        let calendar = PivotDate.calendar
        let targetRule = data.rules[target.id] ?? .defaultRule(for: target)
        guard targetRule.flexibility != .fixed, targetRule.travelConfirmed, !target.isAllDay else { return [] }
        let duration = target.end.timeIntervalSince(target.start)
        guard duration > 0 else { return [] }
        let before = Double(targetRule.travelBeforeMinutes) * 60
        let after = Double(targetRule.travelAfterMinutes) * 60
        let effective = plannedEvents(events, data: data)
        let horizon = calendar.date(byAdding: .day, value: max(1, min(days, 7)), to: calendar.startOfDay(for: now))!
        // An unconfigured journey around another out-of-home event is not a zero-minute journey.
        guard !effective.contains(where: { item in
            item.id != target.id && !item.isAllDay && item.end > now && item.start < horizon
                && !item.location.isEmpty && !(data.rules[item.id]?.travelConfirmed ?? false)
        }) else { return [] }
        var results: [RecoverySuggestion] = []
        for day in 0..<max(1, min(days, 7)) {
            guard let date = calendar.date(byAdding: .day, value: day, to: calendar.startOfDay(for: now)),
                  let dayStart = calendar.date(bySettingHour: data.settings.quietEndHour, minute: 0, second: 0, of: date),
                  let dayEnd = calendar.date(bySettingHour: data.settings.quietStartHour, minute: 0, second: 0, of: date) else { continue }
            var cursor = max(now, dayStart)
            let blocks = effective.filter { $0.id != target.id && !$0.isAllDay && $0.end > cursor && $0.start < dayEnd }
                .map { item -> (Date, Date) in
                    let rule = data.rules[item.id] ?? .defaultRule(for: item)
                    return (item.start.addingTimeInterval(-Double(rule.travelBeforeMinutes) * 60), item.end.addingTimeInterval(Double(rule.travelAfterMinutes) * 60))
                }.sorted { $0.0 < $1.0 }
            for block in blocks + [(dayEnd, dayEnd)] {
                let slotEnd = min(block.0, dayEnd)
                if slotEnd.timeIntervalSince(cursor) >= before + duration + after {
                    let start = cursor.addingTimeInterval(before)
                    results.append(.init(start: start, end: start.addingTimeInterval(duration), explanation: "Recupero completo: \(target.durationMinutes) minuti. Tragitto prima: \(targetRule.travelBeforeMinutes) minuti; dopo: \(targetRule.travelAfterMinutes) minuti. Nessun altro evento viene spostato."))
                }
                cursor = max(cursor, block.1)
                if cursor >= dayEnd || results.count >= 3 { break }
            }
            if results.count >= 3 { break }
        }
        return Array(results.prefix(3))
    }
    static func effectiveEvents(_ events: [CalendarItem], data: AppData) -> [CalendarItem] {
        EventCoalescer.unique(events, data: data).map { item in
            guard let move = data.moves.last(where: { $0.source.id == item.id && !$0.syncedToCalendar }) else { return item }
            guard CoachPlanner.matchesPlanSnapshot(move.source, item) else { return item }
            var changed = item
            changed.start = move.proposedStart
            changed.end = move.proposedEnd
            return changed
        }
    }
    static func preferredEvent(_ events: [CalendarItem], data: AppData, now: Date) -> CalendarItem? {
        let relevant = plannedEvents(events, data: data).filter {
            !$0.isAllDay && $0.occurs(on: now) && ![Completion.completed, .partial, .skipped].contains(data.records[$0.id]?.status ?? .pending)
        }
        if let running = relevant.first(where: { data.records[$0.id]?.status == .running }) { return running }
        if let current = relevant.first(where: { $0.start <= now && $0.end > now && data.records[$0.id]?.status != .completed }) { return current }
        return relevant.filter { $0.end <= now && (data.records[$0.id] == nil || data.records[$0.id]?.status == .pending) }.max { $0.end < $1.end }
            ?? relevant.first(where: { $0.start > now })
    }
    static func isStudyPriority(_ data: AppData, now: Date) -> Bool {
        data.settings.studyMustTakePriority && (data.settings.studyPriorityFrom.map { now >= $0 } ?? true)
    }
    static let universityOffNote = "Università: oggi non frequento le lezioni."
    static func universityAttendance(on day: Date, events: [CalendarItem], data: AppData) -> Bool? {
        if let answer = data.checkIns[PivotDate.key(day)]?.universityAttendance { return answer }
        // An explicit instruction in the day's routine is not an inferred cancellation.
        if events.contains(where: { $0.kind == .routine && PivotDate.key($0.start) == PivotDate.key(day) && $0.notes.contains(universityOffNote) }) { return false }
        return nil
    }
    static func plannedEvents(_ events: [CalendarItem], data: AppData) -> [CalendarItem] {
        plannedEffectiveEvents(effectiveEvents(events, data: data), data: data)
    }
    static func plannedEffectiveEvents(_ events: [CalendarItem], data: AppData) -> [CalendarItem] {
        events.filter {
            $0.kind != .university || universityAttendance(on: $0.start, events: events, data: data) != false
        }
    }
    static func overlaps(on day: Date, events: [CalendarItem], data: AppData) -> [(CalendarItem, CalendarItem)] {
        overlapsInPlannedEvents(on: day, events: plannedEvents(events, data: data))
    }
    static func overlapsInPlannedEvents(on day: Date, events: [CalendarItem]) -> [(CalendarItem, CalendarItem)] {
        let items = events.filter { !$0.isAllDay && $0.occurs(on: day) }.sorted { $0.start < $1.start }
        var pairs: [(CalendarItem, CalendarItem)] = []
        for i in items.indices {
            for j in items.indices where j > i {
                if items[j].start >= items[i].end { break }
                if items[i].start < items[j].end { pairs.append((items[i], items[j])) }
            }
        }
        return pairs
    }
}
