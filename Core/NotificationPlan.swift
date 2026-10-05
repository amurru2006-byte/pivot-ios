import Foundation

struct PlannedNotification {
    var date: Date
    var id: String
    var title: String
    var body: String
    var priority: Int
    var eventID: String? = nil
    var destination: String = "event"
}

enum NotificationPlan {
    static func requests(events: [CalendarItem], data: AppData, now: Date, capacity: Int = 60) -> [PlannedNotification] {
        let horizon = now.addingTimeInterval(7 * 86400)
        let calendar = PivotDate.calendar
        var requests: [PlannedNotification] = []
        func add(_ date: Date, _ id: String, _ title: String, _ body: String, priority: Int = 1, eventID: String? = nil, destination: String = "event") {
            guard date > now, date < horizon else { return }
            let hour = calendar.component(.hour, from: date)
            guard hour >= data.settings.quietEndHour && hour < data.settings.quietStartHour else { return }
            requests.append(.init(date: date, id: id, title: title, body: body, priority: priority, eventID: eventID, destination: destination))
        }
        // Use the same deduplicated, attendance-aware program as the home screen.
        for event in Planner.plannedEvents(events, data: data) where !event.isAllDay {
            let record = data.records[event.id]
            let missingCompensation = [.tutoring, .work].contains(event.kind) && [Completion.completed, .partial].contains(record?.status ?? .pending)
                && record?.tutoringAnswered != true && !data.income.contains(where: { $0.calendarEventID == event.id || $0.id == record?.incomeID })
            guard missingCompensation || ![Completion.completed, .partial, .skipped].contains(record?.status ?? .pending) else { continue }
            if event.kind == .meal {
                for minutes in [30, 10] {
                    add(event.start.addingTimeInterval(-Double(minutes) * 60), "meal-\(event.id)-\(minutes)", event.title, "Tra \(minutes) minuti. Apri Pivot per le indicazioni del pasto.", priority: 0, eventID: event.id)
                }
            }
            if event.title.lowercased().contains("sveglia") {
                let day = PivotDate.key(event.start)
                let didStart = data.records.values.contains {
                    PivotDate.key($0.snapshot.start) == day && $0.actualStart != nil && $0.health == nil && $0.healthSleep == nil
                        && !EventCoalescer.normalized($0.snapshot.title).contains("sonno")
                }
                if !didStart && (data.checkIns[day]?.energyMorning == nil || data.checkIns[day]?.moodMorning == nil) {
                    add(event.end.addingTimeInterval(Double(data.settings.morningDelayMinutes) * 60), "morning-\(day)", "Come è iniziata la giornata?", "Energia e umore dopo la routine. I dati disponibili del sonno arrivano da Salute.", priority: 0, destination: "checkin")
                }
                continue
            }
            guard event.kind != .routine else { continue }
            if event.kind != .meal && !missingCompensation {
                add(event.start.addingTimeInterval(-600), "before-\(event.id)", event.title, "Tra 10 minuti. Non serve avviare un timer per segnare l’esito.", priority: 1, eventID: event.id)
            }
            add(event.end, "event-\(event.id)-0", missingCompensation ? "Manca il compenso della ripetizione" : "\(event.title): com'è andata?", missingCompensation ? "Registra il compenso e l'eventuale incasso per: \(event.title)." : "Apri Pivot per rispondere. Puoi rimandare senza perdere la domanda.", eventID: event.id)
            if data.settings.repeatMissedNotifications {
                add(event.end.addingTimeInterval(1800), "event-\(event.id)-30", "Quando hai un momento", "Com’è andata: \(event.title)? Dopo questo avviso resta nel riepilogo serale.", priority: 2, eventID: event.id)
            }
        }
        for day in 0...6 {
            let date = calendar.date(byAdding: .day, value: day, to: now)!
            let time = calendar.date(bySettingHour: data.settings.eveningHour, minute: data.settings.eveningMinute, second: 0, of: date)!
            let missingCardio = WorkoutContext.missingCardio(events: events, data: data, now: time)
            add(time, "evening-\(PivotDate.key(date))", "Resoconto della giornata", missingCardio.isEmpty ? "Controlla le risposte mancanti e condividi il resoconto quando vuoi." : "Controlla anche il cardio da chiarire: il Coach ti chiede se l’hai svolto o recuperato.", priority: 0, destination: missingCardio.isEmpty ? "diary" : "coach")
        }
        // Reserve the finite iOS queue for meals/check-ins before optional follow-ups.
        let chosen = requests.sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id < $1.id
        }.prefix(max(0, capacity))
        return chosen.sorted { $0.date < $1.date }
    }
}
