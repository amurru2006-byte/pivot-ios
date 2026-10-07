import Foundation

enum EventAutofill {
    /// Only an explicit action invokes this. Reopening never reapplies defaults.
    static func complete(_ record: inout EventRecord, event: CalendarItem, now: Date = Date()) {
        record.status = .completed
        if !event.isAllDay && event.end > event.start {
            let startMissing = record.actualStart == nil, endMissing = record.actualEnd == nil
            // Never mix an actual endpoint with a guessed calendar endpoint.
            if startMissing && endMissing {
                record.actualStart = event.start; record.actualEnd = event.end
                record.timingFromCalendar = true
            }
            if record.activeMinutes == 0, let start = record.actualStart, let end = record.actualEnd, end > start {
                record.activeMinutes = Int(end.timeIntervalSince(start) / 60)
            }
        }
        if event.kind == .meal && record.followedMeal == nil { record.followedMeal = true }
        // No fabricated sensations, exercise sets, sleep scores or receipts.
        record.updatedAt = now
    }
}
