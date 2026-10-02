import Foundation

// Calendar imports can expose the same appointment through Google and iCloud.
// Only collapse matching occurrences; the source calendars and stored data stay intact.
enum EventCoalescer {
    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    static func matches(_ a: CalendarItem, _ b: CalendarItem) -> Bool {
        if a.id == b.id { return true }
        guard !normalized(a.title).isEmpty, normalized(a.title) == normalized(b.title),
              normalized(a.calendarTitle) == normalized(b.calendarTitle) else { return false }
        let sameTimes = abs(a.start.timeIntervalSince(b.start)) < 1 && abs(a.end.timeIntervalSince(b.end)) < 1
        if a.calendarIdentifier == b.calendarIdentifier {
            return a.eventIdentifier == b.eventIdentifier && sameTimes
        }
        // Different appointments in the same account must not collapse just because their names match.
        if let first = a.sourceIdentifier, let second = b.sourceIdentifier {
            if first == second { return false }
        } else {
            // Old snapshots without account metadata need a shared UID, not just matching names.
            guard a.externalIdentifier != nil && a.externalIdentifier == b.externalIdentifier else { return false }
        }
        if !a.location.isEmpty && !b.location.isEmpty && normalized(a.location) != normalized(b.location) { return false }
        if sameTimes { return true }
        // A stale all-day import must not override a matching timed appointment.
        if a.isAllDay != b.isAllDay {
            let allDay = a.isAllDay ? a : b, timed = a.isAllDay ? b : a
            return allDay.start <= timed.start && allDay.end >= timed.end
        }
        // A shared UID is an occurrence match only within the same local date and overlapping time.
        return a.externalIdentifier != nil && a.externalIdentifier == b.externalIdentifier
            && PivotDate.key(a.start) == PivotDate.key(b.start) && a.start < b.end && b.start < a.end
    }
    static func savedOccurrence(_ snapshot: CalendarItem, _ current: CalendarItem) -> Bool {
        if matches(snapshot, current) { return true }
        return snapshot.calendarIdentifier == current.calendarIdentifier
            && snapshot.eventIdentifier == current.eventIdentifier
            && PivotDate.key(snapshot.start) == PivotDate.key(current.start)
    }
    private static func prefer(_ a: CalendarItem, over b: CalendarItem) -> Bool {
        if a.isAllDay != b.isAllDay { return !a.isAllDay }
        func google(_ item: CalendarItem) -> Bool {
            let name = item.sourceTitle?.lowercased() ?? ""
            return name.contains("google") || name.contains("gmail")
        }
        if google(a) != google(b) { return google(a) }
        if a.calendarModifiedAt != b.calendarModifiedAt {
            return (a.calendarModifiedAt ?? .distantPast) > (b.calendarModifiedAt ?? .distantPast)
        }
        if a.writable != b.writable { return a.writable }
        return a.id < b.id
    }
    static func unique(_ events: [CalendarItem], data: AppData) -> [CalendarItem] {
        var groups: [[CalendarItem]] = []
        for event in events {
            if let index = groups.firstIndex(where: { $0.contains(where: { matches($0, event) }) }) {
                groups[index].append(event)
            } else { groups.append([event]) }
        }
        return groups.map { group in
            var chosen = group.sorted { prefer($0, over: $1) }[0]
            // Use the original iCloud calendar's exact color when a Google import differs.
            if let original = group.first(where: { ($0.sourceTitle ?? "").lowercased().contains("icloud") }) {
                chosen.colorHex = original.colorHex
            }
            // Keep an existing answer/timer under its original ID, while displaying current calendar metadata.
            let records = data.records.values.filter { record in group.contains(where: { savedOccurrence(record.snapshot, $0) }) }
            if let saved = records.sorted(by: { a, b in
                if (a.status == .running) != (b.status == .running) { return a.status == .running }
                if (a.status != .pending) != (b.status != .pending) { return a.status != .pending }
                if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
                return a.id < b.id
            }).first { chosen.id = saved.id }
            else if let move = data.moves.last(where: { move in group.contains(where: { matches(move.source, $0) }) }) {
                chosen.id = move.source.id
            }
            return chosen
        }.sorted { a, b in a.start == b.start ? a.id < b.id : a.start < b.start }
    }
}
