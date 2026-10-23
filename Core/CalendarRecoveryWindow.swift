import Foundation

struct CalendarRecoveryWindow: Equatable {
    var occupiedStart: Date
    var activityStart: Date
    var activityEnd: Date
    var occupiedEnd: Date
}

enum CalendarRecoveryWindows {
    /// Fits the full budget around every other appointment and its confirmed buffers.
    /// It prepares windows only; it does not apply changes or relax CoachPlanner's guard.
    static func find(target: CalendarItem, budget: CalendarTimeBudget, events: [CalendarItem], data: AppData,
                     otherBudgets: [String: CalendarTimeBudget] = [:], now: Date, days: Int = 3,
                     excludingDays: [Date] = [], within allowedIntervals: [DateInterval]? = nil) -> [CalendarRecoveryWindow] {
        // Constraints are applied BEFORE collecting the first three windows.
        // Filtering three unrestricted results afterwards can hide every valid
        // later-day alternative. An explicit empty set means no allowed time.
        let allowed = allowedIntervals?.sorted { $0.start < $1.start }
        if let allowed {
            guard (1...7).contains(allowed.count), allowed.allSatisfy({ interval in
                [interval.start, interval.end].allSatisfy {
                    $0.timeIntervalSince1970.isFinite && (0...253_402_300_799).contains($0.timeIntervalSince1970)
                } && interval.start < interval.end
            }), zip(allowed, allowed.dropFirst()).allSatisfy({ pair in pair.0.end <= pair.1.start }) else { return [] }
        }
        let rule = EventRule.effective(for: target, data: data)
        let canonical = EventCoalescer.unique(events, data: data)
        guard let current = canonical.first(where: { $0.id == target.id }),
              CoachPlanner.matchesSnapshot(target, current), target.writable, !target.isAllDay,
              rule.flexibility != .fixed, rule.travelConfirmed,
              budget == CalendarTimeBudget.confirmed(activityMinutes: budget.activityMinutes, rule: rule,
                                                     preparationMinutes: budget.preparationMinutes, marginMinutes: budget.marginMinutes),
              !(data.moves.contains { !$0.syncedToCalendar && $0.source.id == target.id }),
              ![Completion.running, .completed, .partial].contains(data.records[target.id]?.status ?? .pending),
              now.timeIntervalSinceReferenceDate.isFinite,
              excludingDays.count <= 7, excludingDays.allSatisfy({ $0.timeIntervalSinceReferenceDate.isFinite }),
              (0...23).contains(data.settings.quietEndHour), (0...23).contains(data.settings.quietStartHour),
              data.settings.quietEndHour < data.settings.quietStartHour else { return [] }
        let effective = Planner.plannedEvents(events, data: data).filter { $0.id != target.id }
        let calendar = PivotDate.calendar
        let count = max(1, min(days, 7))
        var windows: [CalendarRecoveryWindow] = []
        for offset in 0..<count {
            let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
            // Exclude before collecting the first three results, not after:
            // otherwise an excluded early day could hide valid later windows.
            if excludingDays.contains(where: { calendar.isDate($0, inSameDayAs: day) }) { continue }
            let start = calendar.date(bySettingHour: data.settings.quietEndHour, minute: 0, second: 0, of: day)!
            let end = calendar.date(bySettingHour: data.settings.quietStartHour, minute: 0, second: 0, of: day)!
            let ranges = allowed.map { intervals in
                intervals.compactMap { interval -> DateInterval? in
                    let lower = max(max(now, start), interval.start), upper = min(end, interval.end)
                    return lower < upper ? DateInterval(start: lower, end: upper) : nil
                }
            } ?? (max(now, start) < end ? [DateInterval(start: max(now, start), end: end)] : [])
            if ranges.isEmpty { continue }
            // Include adjacent-day travel that crosses into the planning window.
            let relevant = effective.filter { $0.start < end.addingTimeInterval(86400) && $0.end > start.addingTimeInterval(-86400) }
            // Busy all-day items lack availability metadata: ask before treating them as free.
            if relevant.contains(where: { $0.isAllDay && $0.start < end && $0.end > start }) { continue }
            var unavailable = false
            let blocks = relevant.compactMap { event -> (Date, Date)? in
                guard !event.isAllDay else { return nil }
                let other = EventRule.effective(for: event, data: data)
                guard event.end > event.start,
                      (0...1440).contains(other.travelBeforeMinutes), (0...1440).contains(other.travelAfterMinutes),
                      event.location.isEmpty || other.travelConfirmed else { unavailable = true; return nil }
                let before: Int, after: Int, activityEnd: Date
                if let otherBudget = otherBudgets[event.id] {
                    guard otherBudget == CalendarTimeBudget.confirmed(activityMinutes: otherBudget.activityMinutes,
                        rule: other, preparationMinutes: otherBudget.preparationMinutes, marginMinutes: otherBudget.marginMinutes) else {
                        unavailable = true; return nil
                    }
                    before = otherBudget.beforeMinutes; after = otherBudget.afterMinutes
                    activityEnd = event.start.addingTimeInterval(Double(otherBudget.activityMinutes) * 60)
                } else {
                    before = other.travelBeforeMinutes; after = other.travelAfterMinutes
                    activityEnd = event.end
                }
                return (event.start.addingTimeInterval(-Double(before) * 60), activityEnd.addingTimeInterval(Double(after) * 60))
            }.filter { $0.0 < end && $0.1 > max(now, start) }.sorted { $0.0 < $1.0 }
            if unavailable { continue }
            for range in ranges {
                var cursor = range.start
                for block in blocks.filter({ $0.0 < range.end && $0.1 > cursor }) + [(range.end, range.end)] {
                    let occupiedEnd = cursor.addingTimeInterval(Double(budget.occupiedMinutes) * 60)
                    if occupiedEnd <= min(block.0, range.end) {
                        let activityStart = cursor.addingTimeInterval(Double(budget.beforeMinutes) * 60)
                        let activityEnd = activityStart.addingTimeInterval(Double(budget.activityMinutes) * 60)
                        windows.append(.init(occupiedStart: cursor, activityStart: activityStart,
                                             activityEnd: activityEnd, occupiedEnd: occupiedEnd))
                        if windows.count == 3 { return windows }
                    }
                    cursor = max(cursor, block.1)
                    if cursor >= range.end { break }
                }
            }
        }
        return windows
    }
}
