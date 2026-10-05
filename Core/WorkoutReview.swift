import Foundation

struct WorkoutReview: Codable, Identifiable, Equatable {
    var id: String { workout.id }
    var workout: HealthWorkoutSummary
    var eventIDs: [String]
    var dismissed = false
    var resolved = false
}

struct ActualWorkoutDraft: Codable, Identifiable {
    var id = UUID()
    var source: CalendarItem
    var health: HealthWorkoutSummary?
    var start: Date
    var end: Date?
    var wake: Date?
    var bedtime: Date?
    var breakfastDone: Bool?
    var breakfastStart: Date?
    var breakfastEnd: Date?
    var contextEvents: [CalendarItem]? = nil
    var wakeEnd: Date? = nil
    var healthDerived: Bool? = nil
}

enum WorkoutContext {
    static func strength(_ value: HealthWorkoutSummary) -> Bool { ["strength", "functional", "hiit"].contains(value.type) }
    // These are adjustable attention thresholds, not a medical measure of intensity.
    static func significantCardio(_ value: HealthWorkoutSummary, settings: Settings) -> Bool {
        guard ["walk", "hike", "treadmill", "run", "cycle"].contains(value.type) else { return false }
        let minutes = max(5, settings.cardioReviewMinimumMinutes ?? 20)
        let calories = max(0, settings.cardioReviewMinimumCalories ?? 100)
        return value.durationSeconds >= minutes * 60 && (value.activeCalories.map { $0.isFinite && $0 >= Double(calories) } ?? false)
    }
    static func refreshed(_ values: [HealthWorkoutSummary], events: [CalendarItem], data: AppData, now: Date) -> [WorkoutReview] {
        let old = data.workoutReviews ?? []
        let planned = Planner.plannedEvents(events, data: data)
        var result = old
        for value in values where value.end <= now && value.start >= now.addingTimeInterval(-7 * 86400) {
            guard !old.contains(where: { $0.id == value.id }),
                  !data.records.values.contains(where: { $0.health?.id == value.id }) else { continue }
            let candidates = planned.filter { event in
                guard event.kind == .workout, !event.isAllDay, PivotDate.calendar.isDate(event.start, inSameDayAs: value.start),
                      ![Completion.completed, .partial, .running].contains(data.records[event.id]?.status ?? .pending) else { return false }
                if strength(value) { return CardioKind.suggested(event.title) == nil }
                return significantCardio(value, settings: data.settings) && CardioKind.suggested(event.title) != nil
            }
            guard !candidates.isEmpty else { continue }
            result.append(.init(workout: value, eventIDs: candidates.map(\.id)))
        }
        return result.filter { $0.workout.start >= now.addingTimeInterval(-30 * 86400) }
    }
    static func missingCardio(events: [CalendarItem], data: AppData, now: Date) -> [CalendarItem] {
        guard PivotDate.calendar.component(.hour, from: now) >= data.settings.eveningHour else { return [] }
        return Planner.plannedEvents(events, data: data).filter {
            $0.occurs(on: now) && $0.kind == .workout && CardioKind.suggested($0.title) != nil && $0.end <= now &&
            ![Completion.completed, .partial, .skipped].contains(data.records[$0.id]?.status ?? .pending)
        }
    }
    static func statedStart(_ text: String, now: Date) -> Date? {
        let normalized = text.lowercased()
        guard !["non sono", "non ho", "domani", "vorrei", "ipotizziamo", "se vado", "andrò", "andro"].contains(where: normalized.contains),
              ["sono andato", "sono andata", "ho iniziato", "mi sono allenato", "mi sono allenata"].contains(where: normalized.contains),
              ["pale", "allenament"].contains(where: normalized.contains) else { return nil }
        let pattern = #"\b(?:palestra|pale|allenamento|allenato|allenata)\s[^!?\n]{0,45}?\b(?:alle|dalle)\s+(\d{1,2})[.:](\d{2})\s*(am|pm)?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
              let hr = Range(match.range(at: 1), in: normalized), let mr = Range(match.range(at: 2), in: normalized),
              var hour = Int(normalized[hr]), let minute = Int(normalized[mr]), (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        if let r = Range(match.range(at: 3), in: normalized) {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (normalized[r] == "pm" ? 12 : 0)
        }
        let day = normalized.contains("ieri") ? PivotDate.calendar.date(byAdding: .day, value: -1, to: now)! : now
        guard let result = PivotDate.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day), result <= now else { return nil }
        return result
    }
    static func moves(_ draft: ActualWorkoutDraft, events: [CalendarItem]) -> [PlanMove] {
        guard let end = draft.end else { return [] }
        var values = [PlanMove(source: draft.source, proposedStart: draft.start, proposedEnd: end)]
        let context = draft.contextEvents ?? events
        let daily = context.filter { !$0.isAllDay && PivotDate.calendar.isDate($0.start, inSameDayAs: draft.start) }
        if let wake = draft.wake, let end = draft.wakeEnd, let event = daily.first(where: { EventCoalescer.normalized($0.title) == "sveglia" }) {
            values.append(.init(source: event, proposedStart: wake, proposedEnd: end))
        }
        if let bedtime = draft.bedtime, let wake = draft.wake, let event = context.first(where: {
            $0.kind == .routine && EventCoalescer.normalized($0.title).contains("sonno") && PivotDate.calendar.isDate($0.end, inSameDayAs: draft.start)
        }) { values.append(.init(source: event, proposedStart: bedtime, proposedEnd: wake)) }
        if draft.breakfastDone == true, let start = draft.breakfastStart, let end = draft.breakfastEnd,
           let event = daily.first(where: { $0.kind == .meal && EventCoalescer.normalized($0.title).contains("colazione") }) {
            values.append(.init(source: event, proposedStart: start, proposedEnd: end))
        }
        return values
    }
    static func validate(_ draft: ActualWorkoutDraft, events: [CalendarItem], now: Date) -> String? {
        guard draft.source.kind == .workout, !draft.source.isAllDay, let end = draft.end, end > draft.start, end <= now,
              end.timeIntervalSince(draft.start) <= 24 * 3600 else { return "Indica inizio e fine reali di un allenamento già terminato." }
        guard let wake = draft.wake, wake <= draft.start,
              PivotDate.calendar.isDate(wake, inSameDayAs: draft.start) else { return "Conferma la sveglia reale, prima dell’allenamento." }
        if let bedtime = draft.bedtime, bedtime >= wake || wake.timeIntervalSince(bedtime) > 48 * 3600 { return "Controlla data e ora in cui sei andato a letto." }
        guard draft.breakfastDone != nil else { return "Conferma se hai fatto colazione. Non lo deduco dall’allenamento." }
        let daily = events.filter { !$0.isAllDay && PivotDate.calendar.isDate($0.start, inSameDayAs: draft.start) }
        if daily.contains(where: { EventCoalescer.normalized($0.title) == "sveglia" }) {
            guard let end = draft.wakeEnd, end > wake, end <= draft.start else { return "Conferma quando hai finito di prepararti, prima della palestra." }
        }
        guard daily.filter({ EventCoalescer.normalized($0.title) == "sveglia" }).count <= 1,
              daily.filter({ $0.kind == .meal && EventCoalescer.normalized($0.title).contains("colazione") }).count <= 1,
              events.filter({ $0.kind == .routine && EventCoalescer.normalized($0.title).contains("sonno") && PivotDate.calendar.isDate($0.end, inSameDayAs: draft.start) }).count <= 1 else { return "Ci sono più sveglie, colazioni o eventi sonno: scegli gli eventi nei dettagli prima di modificare il Calendario." }
        if draft.breakfastDone == true {
            guard let start = draft.breakfastStart, let end = draft.breakfastEnd, start >= wake, end > start, end <= now else { return "Indica gli orari reali della colazione." }
            if start < draft.end! && end > draft.start { return "Colazione e allenamento hanno orari sovrapposti: correggili." }
        }
        for move in moves(draft, events: events) {
            guard let current = events.first(where: { $0.id == move.source.id }), CoachPlanner.matchesSnapshot(move.source, current) else { return "Il Calendario è cambiato: aggiorna e prepara di nuovo la conferma." }
        }
        return nil
    }
    static func applyLocally(_ draft: ActualWorkoutDraft, events: [CalendarItem], data: inout AppData, synced: Bool, now: Date) {
        guard validate(draft, events: events, now: now) == nil else { return }
        let moves = moves(draft, events: events)
        for var move in moves {
            let check = data.checkIns[PivotDate.key(draft.start)]
            move.healthDerived = draft.health != nil || (check?.sleep?.importedFromHealth == true) || (check?.healthWakeTime != nil && check?.healthWakeTime == draft.wake) ? true : nil
            move.syncedToCalendar = synced
            data.moves.removeAll { !$0.syncedToCalendar && $0.source.id == move.source.id }; data.moves.append(move)
        }
        var record = data.records[draft.source.id] ?? .init(id: draft.source.id, snapshot: draft.source)
        record.status = .completed; record.actualStart = draft.start; record.actualEnd = draft.end
        record.activeMinutes = draft.health.map { $0.durationSeconds / 60 } ?? Int(draft.end!.timeIntervalSince(draft.start) / 60)
        record.health = draft.health; record.updatedAt = now; data.records[record.id] = record
        let key = PivotDate.key(draft.start); var check = data.checkIns[key] ?? .init(id: key)
        check.wakeTime = draft.wake
        if let bedtime = draft.bedtime {
            var sleep = check.sleep ?? SleepRecord()
            if sleep.bedtime != bedtime || check.healthWakeTime != draft.wake {
                sleep = SleepRecord(); sleep.bedtime = bedtime
            }
            check.sleep = sleep
        }
        data.checkIns[key] = check
        for move in moves.dropFirst() {
            var r = data.records[move.source.id] ?? .init(id: move.source.id, snapshot: move.source)
            r.status = .completed; r.actualStart = move.proposedStart; r.actualEnd = move.proposedEnd
            r.activeMinutes = move.source.title.lowercased().contains("sonno") ? (check.sleep?.durationSeconds ?? 0) / 60 : Int(move.proposedEnd.timeIntervalSince(move.proposedStart) / 60)
            r.updatedAt = now
            data.records[r.id] = r
        }
        if let id = draft.health?.id, let index = data.workoutReviews?.firstIndex(where: { $0.id == id }) { data.workoutReviews?[index].resolved = true }
        data.actualWorkoutDraft = nil
    }
}
