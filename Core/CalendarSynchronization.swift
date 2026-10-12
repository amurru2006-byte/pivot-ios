import Foundation

/// Deterministic rules shared by the UI and EventKit bridge. No calendar
/// change is inferred: a write is possible only after real times were saved.
enum CalendarSynchronization {
    struct ActualTiming: Equatable {
        var start: Date
        var end: Date
    }

    static func actualTiming(for record: EventRecord, event: CalendarItem) -> ActualTiming? {
        guard !event.isAllDay,
              record.timingFromCalendar != true,
              record.status != .pending,
              record.status != .running,
              record.status != .skipped,
              let start = record.actualStart,
              let end = record.actualEnd,
              end > start else { return nil }
        return ActualTiming(start: start, end: end)
    }

    static func needsCalendarUpdate(_ timing: ActualTiming, event: CalendarItem) -> Bool {
        abs(timing.start.timeIntervalSince(event.start)) >= 1
            || abs(timing.end.timeIntervalSince(event.end)) >= 1
    }

    /// A deleted calendar occurrence must not survive as an unanswered diary
    /// item. It remains only when Pivot contains genuine history from the user,
    /// Health, a workout, or an associated payment.
    static func hasMeaningfulHistory(_ record: EventRecord) -> Bool {
        record.status != .pending
            || record.actualStart != nil
            || record.actualEnd != nil
            || record.activeMinutes > 0
            || !record.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !record.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || record.hungerBefore != nil
            || record.hungerAfter != nil
            || record.energy != nil
            || record.fatigue != nil
            || record.followedMeal != nil
            || record.reflection != nil
            || record.study != nil
            || record.incomeID != nil
            || record.tutoringAnswered == true
            || !(record.reminders ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || record.cardio != nil
            || record.health != nil
            || record.healthSleep != nil
    }
}
