import Foundation

/// Deterministic alternatives over a bounded horizon. No training order,
/// recovery-day requirement or medical restriction is inferred.
enum RecoveryForecast {
    static func options(targetID: String, events: [CalendarItem], data: AppData, now: Date,
                        days: Int = 7, preferredBand: TrainingDurationTimeBand? = nil) -> [CoachOption] {
        guard (1...7).contains(days), now.timeIntervalSinceReferenceDate.isFinite,
              let target = EventCoalescer.unique(events, data: data).first(where: { $0.id == targetID }),
              target.end <= now, target.writable,
              [.pending, .skipped].contains(data.records[targetID]?.status ?? .pending),
              target.start.timeIntervalSinceReferenceDate.isFinite, target.end.timeIntervalSinceReferenceDate.isFinite else { return [] }
        let seconds = target.end.timeIntervalSince(target.start)
        guard seconds > 0 && seconds <= 86400 else { return [] }
        let rule = EventRule.effective(for: target, data: data)
        guard let budget = CalendarTimeBudget.confirmed(activityMinutes: Int(ceil(seconds / 60)), rule: rule,
                                                       preparationMinutes: 0) else { return [] }
        var searchData = data
        if let preferredBand {
            let interval: (Int, Int)
            switch preferredBand {
            case .morning: interval = (0, 12)
            case .afternoon: interval = (12, 18)
            case .evening: interval = (18, 24)
            }
            searchData.settings.quietEndHour = max(data.settings.quietEndHour, interval.0)
            searchData.settings.quietStartHour = min(data.settings.quietStartHour, interval.1)
        }
        let earliest = now.addingTimeInterval(5 * 60)
        let windows = CalendarRecoveryWindows.find(target: target, budget: budget, events: events,
                                                  data: searchData, now: earliest, days: days)
        return windows.enumerated().compactMap { index, window in
            let move = PlanMove(source: target, proposedStart: window.activityStart,
                                proposedEnd: window.activityStart.addingTimeInterval(seconds))
            let option = CoachOption(title: "Recupero \(index + 1)",
                                     explanation: "\(target.title) · \(PivotDate.shortDate(move.proposedStart)) \(PivotDate.time(move.proposedStart))–\(PivotDate.time(move.proposedEnd))",
                                     consequences: "Durata integrale del calendario, inclusi cambio e preparazione già previsti. Tragitto prima: \(rule.travelBeforeMinutes) min; dopo: \(rule.travelAfterMinutes) min, da ricontrollare per questo orario. Nessun altro evento viene spostato. Nessuna pausa obbligatoria tra sedute è stata aggiunta.",
                                     moves: [move], createdAt: now)
            return CoachPlanner.validate(option, events: events, data: data, now: now) == nil ? option : nil
        }
    }
}
