import Foundation

enum RecoveryPreference: String, Codable, CaseIterable {
    case recover, optional, doNotRecover
}

/// Review and scheduling eligibility are deliberately separate from diary completion.
/// No missing diary entry, old appointment or sleep sample fabricates an outcome.
struct DayRecoveryItem: Identifiable, Equatable {
    enum State: String {
        case planned, needsReview, running, completed, partialNeedsReview
        case recoveryCandidate, optionalRecovery, notToRecover, recoveryPreferenceMissing
    }
    var id: String { event.id }
    var event: CalendarItem
    var state: State
    var preference: RecoveryPreference?
    var overlapsRecordedSleep: Bool
    var hasPendingMove: Bool
    var calendarWritable: Bool { event.writable }
}

struct DayWakeContext: Equatable {
    enum Source: String { case manual, health }
    var wakeTime: Date
    var source: Source
    var sleepStart: Date?

    static func make(data: AppData, now: Date) -> Self? {
        guard let check = data.checkIns[PivotDate.key(now)], let wake = check.wakeTime,
              wake.timeIntervalSinceReferenceDate.isFinite, wake <= now,
              PivotDate.calendar.isDate(wake, inSameDayAs: now) else { return nil }
        let health = data.settings.healthEnabled == true && check.sleep?.importedFromHealth == true
            && check.healthWakeTime == wake
        // A saved Health-derived time is not a new manual observation after disconnecting Health.
        guard check.healthWakeTime != wake || health else { return nil }
        let sleepStart = health ? check.sleep?.bedtime : nil
        return .init(wakeTime: wake, source: health ? .health : .manual,
                     sleepStart: sleepStart.flatMap { $0.timeIntervalSinceReferenceDate.isFinite && $0 < wake ? $0 : nil })
    }
}

enum DayRecoveryReview {
    /// Preferences are explicit per occurrence here. Reusable UI policy will be
    /// implemented after the user's choice, without matching people by title.
    static func make(events: [CalendarItem], data: AppData, preferences: [String: RecoveryPreference],
                     now: Date, lookbackDays: Int = 7) -> [DayRecoveryItem] {
        let earliest = PivotDate.calendar.date(byAdding: .day, value: -max(0, min(lookbackDays, 30)),
                                               to: PivotDate.calendar.startOfDay(for: now))!
        let tomorrow = PivotDate.calendar.date(byAdding: .day, value: 1, to: PivotDate.calendar.startOfDay(for: now))!
        let wake = DayWakeContext.make(data: data, now: now)
        return Planner.plannedEvents(events, data: data).filter {
            !$0.isAllDay && $0.end > earliest && $0.start < tomorrow && $0.end > $0.start
        }.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }.map { event in
            let preference = preferences[event.id]
            let status = data.records[event.id]?.status ?? .pending
            let pendingMove = data.moves.contains { !$0.syncedToCalendar && $0.source.id == event.id }
            let state: DayRecoveryItem.State
            switch status {
            case .completed: state = .completed
            case .running: state = .running
            case .partial: state = .partialNeedsReview
            case .pending: state = event.start <= now ? .needsReview : .planned
            case .skipped:
                switch preference {
                case .recover: state = .recoveryCandidate
                case .optional: state = .optionalRecovery
                case .doNotRecover: state = .notToRecover
                case nil: state = .recoveryPreferenceMissing
                }
            }
            let sleepOverlap = wake.flatMap { context -> Bool? in
                guard let start = context.sleepStart else { return nil }
                return event.start < context.wakeTime && event.end > start
            } ?? false
            return .init(event: event, state: state, preference: preference,
                         overlapsRecordedSleep: sleepOverlap, hasPendingMove: pendingMove)
        }
    }
}
