import Foundation

/// Descriptive planning context only: no readiness score, medical clearance,
/// diagnosis, inferred completion or inferred location.
struct DayPlanningContext: Equatable {
    enum SleepSource: Equatable { case manual, health }
    var sleepMinutes: Int?
    var sleepSource: SleepSource?
    var reportedEnergy: Int?
    var reportedFatigue: Int?
    var scheduledMinutes: Int
    var freeMinutes: Int
    var unknownTravelCount: Int
    var allDayBusy: Bool
    var missedUnconfirmedCount: Int

    static func make(events: [CalendarItem], data: AppData, now: Date) -> Self? {
        guard now.timeIntervalSinceReferenceDate.isFinite,
              (0...23).contains(data.settings.quietEndHour), (0...23).contains(data.settings.quietStartHour),
              data.settings.quietEndHour < data.settings.quietStartHour,
              let awake = PivotDate.calendar.date(bySettingHour: data.settings.quietEndHour, minute: 0, second: 0, of: now),
              let end = PivotDate.calendar.date(bySettingHour: data.settings.quietStartHour, minute: 0, second: 0, of: now) else { return nil }
        let check = data.checkIns[PivotDate.key(now)]
        let sleep = check?.sleep
        let canUseSleep = sleep?.importedFromHealth != true || data.settings.healthEnabled == true
        let seconds = canUseSleep ? sleep?.durationSeconds : nil
        let sleepMinutes = seconds.flatMap { (1...86400).contains($0) ? Int(ceil(Double($0) / 60)) : nil }
        let isEvening = PivotDate.calendar.component(.hour, from: now) >= 17
        let energy = (isEvening ? (check?.energyEvening ?? check?.energyMorning) : check?.energyMorning).flatMap { (0...10).contains($0) ? $0 : nil }
        let fatigue = (isEvening ? (check?.fatigueEvening ?? check?.fatigueMorning) : check?.fatigueMorning).flatMap { (0...10).contains($0) ? $0 : nil }
        let start = min(end, max(now, awake))
        let effective = Planner.plannedEvents(events, data: data).filter {
            $0.start.timeIntervalSinceReferenceDate.isFinite && $0.end.timeIntervalSinceReferenceDate.isFinite && $0.end > $0.start
        }
        let missed = effective.filter {
            !$0.isAllDay && $0.occurs(on: now) && $0.end < now && (data.records[$0.id]?.status ?? .pending) == .pending
        }.count
        let relevant = effective.filter { $0.start < end.addingTimeInterval(86400) && $0.end > start.addingTimeInterval(-86400) }
        let allDay = relevant.contains { $0.isAllDay && $0.start < end && $0.end > start }
        var unknown = 0
        let blocks = relevant.compactMap { event -> HealthInterval? in
            guard !event.isAllDay else { return nil }
            let rule = EventRule.effective(for: event, data: data)
            let known = rule.travelConfirmed && (0...1440).contains(rule.travelBeforeMinutes) && (0...1440).contains(rule.travelAfterMinutes)
            let before = known ? rule.travelBeforeMinutes : 0, after = known ? rule.travelAfterMinutes : 0
            let from = max(start, event.start.addingTimeInterval(-Double(before) * 60))
            let to = min(end, event.end.addingTimeInterval(Double(after) * 60))
            guard to > from else { return nil }
            if !known && !event.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { unknown += 1 }
            return .init(start: from, end: to)
        }
        let duration = max(0, end.timeIntervalSince(start))
        let occupied = allDay ? duration : HealthImport.merged(blocks).reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        return .init(sleepMinutes: sleepMinutes, sleepSource: sleepMinutes == nil ? nil : (sleep?.importedFromHealth == true ? .health : .manual),
                     reportedEnergy: energy, reportedFatigue: fatigue, scheduledMinutes: Int(ceil(occupied / 60)),
                     freeMinutes: max(0, Int(floor((duration - occupied) / 60))), unknownTravelCount: unknown,
                     allDayBusy: allDay, missedUnconfirmedCount: missed)
    }
}
