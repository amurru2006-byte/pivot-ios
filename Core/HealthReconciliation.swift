import Foundation

enum HealthReconciliation {
    static func merge(workouts: [HealthWorkoutSummary], sleeps: [String: HealthSleepSummary],
                      events: [CalendarItem], data: AppData, now: Date) -> AppData? {
        let planned = Planner.plannedEvents(events, data: data)
        let matches = workouts.map { ($0, HealthImport.candidates($0, events: planned)) }.filter { $0.1.count == 1 }
        let matchCounts = Dictionary(matches.compactMap { $0.1.first?.id }.map { ($0, 1) }, uniquingKeysWith: +)
        var next = data, modified = false
        for (workout, candidates) in matches {
            guard let event = candidates.first, matchCounts[event.id] == 1,
                  (CardioKind.suggested(event.title) == nil || WorkoutContext.significantCardio(workout, settings: next.settings)),
                  workout.durationSeconds >= event.durationMinutes * 30,
                  next.records[event.id]?.health?.id != workout.id,
                  (next.records[event.id]?.status ?? .pending) == .pending else { continue }
            HealthImport.apply(workout, to: event, data: &next); modified = true
        }
        let reviews = WorkoutContext.refreshed(workouts, events: events, data: next, now: now)
        if reviews != next.workoutReviews { next.workoutReviews = reviews; modified = true }
        var coach = next.coachState
        for review in reviews where !review.resolved && !review.dismissed {
            let marker = "[Salute \(review.id)]"
            guard !coach.messages.contains(where: { $0.text.contains(marker) }) else { continue }
            coach.messages.append(.init(dayKey: PivotDate.key(review.workout.start), role: .coach,
                text: "Ho trovato \(WorkoutContext.strength(review.workout) ? "un allenamento di forza" : "un’attività cardio significativa") alle \(PivotDate.time(review.workout.start)), da collegare al programma. È l’allenamento del giorno che hai anticipato o spostato? Confermalo qui sotto: sonno e colazione restano da verificare. \(marker)", healthDerived: true))
            next.coachState = coach; modified = true
        }
        for (key, summary) in sleeps {
            var check = next.checkIns[key] ?? DayCheckIn(id: key)
            guard check.sleep == nil || check.sleep?.importedFromHealth == true else { continue }
            if check.sleep?.durationSeconds != summary.durationSeconds || check.healthWakeTime != summary.end {
                check.sleep = SleepRecord(bedtime: summary.start, durationSeconds: summary.durationSeconds,
                    awakenings: summary.awakenings, interruptionSeconds: summary.interruptionSeconds, importedFromHealth: true)
                if check.wakeTime == nil || check.wakeTime == check.healthWakeTime { check.wakeTime = summary.end }
                check.healthWakeTime = summary.end; next.checkIns[key] = check; modified = true
            }
            let sleepEvents = planned.filter { $0.kind == .routine && EventCoalescer.normalized($0.title).contains("sonno") && PivotDate.key($0.end) == key && $0.start < summary.end && $0.end > summary.start }
            if sleepEvents.count == 1, let event = sleepEvents.first, (next.records[event.id]?.status ?? .pending) == .pending {
                var record = next.records[event.id] ?? EventRecord(id: event.id, snapshot: event)
                record.status = .completed; record.actualStart = summary.start; record.actualEnd = summary.end
                record.timingFromCalendar = false
                record.activeMinutes = summary.durationSeconds / 60; record.healthSleep = check.sleep
                next.records[event.id] = record; modified = true
            }
        }
        return modified ? next : nil
    }
}
