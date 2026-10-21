import Foundation

/// Deterministic rules shared by the UI and EventKit bridge. No calendar
/// change is inferred: a write is possible only after real times were saved.
enum CalendarSynchronization {
    struct ActualTiming: Equatable {
        var start: Date
        var end: Date
    }

    /// A one-endpoint correction is a proposal, not a measured second endpoint.
    /// The UI must show both endpoints and obtain explicit confirmation. Keep
    /// absent actual timestamps absent in the activity/financial history.
    static func explicitlyEditedTiming(for record: EventRecord, event: CalendarItem) -> ActualTiming? {
        // Older app versions already marked manual clock corrections with
        // timingFromCalendar=false, but had no pending-confirmation field.
        // Offer those as proposals too; never infer consent from Health data.
        let legacyManual = record.timingFromCalendar == false && record.health == nil && record.healthSleep == nil
        guard record.calendarTimingNeedsConfirmation == true || legacyManual, !event.isAllDay,
              record.status != .running, record.status != .skipped,
              record.actualStart != nil || record.actualEnd != nil else { return nil }
        let start = record.actualStart ?? event.start, end = record.actualEnd ?? event.end
        guard start.timeIntervalSinceReferenceDate.isFinite, end.timeIntervalSinceReferenceDate.isFinite,
              end > start else { return nil }
        return .init(start: start, end: end)
    }

    static func actualTiming(for record: EventRecord, event: CalendarItem) -> ActualTiming? {
        guard !event.isAllDay,
              // Opening/saving a Health-imported activity is not consent to
              // copy its observations into another data store. Explicit clock
              // edits go through the separate, confirmed proposal above.
              record.health == nil, record.healthSleep == nil,
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
