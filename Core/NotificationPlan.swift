import Foundation

struct PlannedNotification {
    var date: Date
    var id: String
    var title: String
    var body: String
    var priority: Int
}

enum NotificationPlan {
    static func requests(events: [CalendarItem], data: AppData, now: Date, capacity: Int = 60) -> [PlannedNotification] {
        let horizon = now.addingTimeInterval(48 * 3600)
        let calendar = PivotDate.calendar
        var requests: [PlannedNotification] = []
        func add(_ date: Date, _ id: String, _ title: String, _ body: String, priority: Int = 1) {
            guard date > now, date < horizon else { return }
            let hour = calendar.component(.hour, from: date)
            guard hour >= data.settings.quietEndHour && hour < data.settings.quietStartHour else { return }
            requests.append(.init(date: date, id: id, title: title, body: body, priority: priority))
        }
        // Use the same deduplicated, attendance-aware program as the home screen.
        for event in Planner.plannedEvents(events, data: data) where !event.isAllDay {
            let record = data.records[event.id]
            let missingCompensation = event.kind == .tutoring && [Completion.completed, .partial].contains(record?.status ?? .pending)
                && record?.tutoringAnswered != true && !data.income.contains(where: { $0.calendarEventID == event.id || $0.id == record?.incomeID })
            guard missingCompensation || ![Completion.completed, .partial, .skipped].contains(record?.status ?? .pending) else { continue }
            if event.kind == .meal {
                for minutes in [30, 10] {
                    add(event.start.addingTimeInterval(-Double(minutes) * 60), "meal-\(event.id)-\(minutes)", event.title, "Tra \(minutes) minuti. Apri Pivot per le indicazioni del pasto.", priority: 0)
                }
            }
            if event.title.lowercased().contains("sveglia") {
                let day = PivotDate.key(event.start)
                let didStart = data.records.values.contains { PivotDate.key($0.snapshot.start) == day && $0.actualStart != nil }
                if !didStart && data.checkIns[day]?.wakeTime == nil {
                    add(event.start.addingTimeInterval(Double(data.settings.morningDelayMinutes) * 60), "morning-\(day)", "Come è iniziata la giornata?", "Registra la sveglia reale, l'energia e l'umore dopo la routine.", priority: 0)
                }
                continue
            }
            guard event.kind != .routine else { continue }
            add(event.end, "event-\(event.id)-0", missingCompensation ? "Manca il compenso della ripetizione" : "\(event.title): com'è andata?", missingCompensation ? "Registra il compenso e l'eventuale incasso per: \(event.title)." : "Segna fatto, parziale o saltato e aggiungi le tue note.")
            add(event.end.addingTimeInterval(1800), "event-\(event.id)-30", "Manca il resoconto", "Devi ancora compilare: \(event.title). Puoi farlo quando sei libero.", priority: 2)
            if data.settings.repeatMissedNotifications {
                for hour in 1...24 {
                    add(event.end.addingTimeInterval(1800 + Double(hour) * 3600), "event-\(event.id)-\(hour)", "Resoconto ancora da compilare", event.title, priority: 2)
                }
            }
        }
        for day in 0...2 {
            let date = calendar.date(byAdding: .day, value: day, to: now)!
            let time = calendar.date(bySettingHour: data.settings.eveningHour, minute: data.settings.eveningMinute, second: 0, of: date)!
            add(time, "evening-\(PivotDate.key(date))", "Resoconto della giornata", "Apri Pivot: controlla le risposte mancanti e condividi il resoconto con ChatGPT.", priority: 0)
        }
        // Reserve the finite iOS queue for meals/check-ins before hourly repeats.
        let chosen = requests.sorted {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id < $1.id
        }.prefix(max(0, capacity))
        return chosen.sorted { $0.date < $1.date }
    }
}
