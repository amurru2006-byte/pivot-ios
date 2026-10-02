import Foundation

// Simulator-only sample data for visual verification. Never enabled in the IPA.
enum PreviewMode {
    static var enabled: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return ProcessInfo.processInfo.arguments.contains("--preview")
        #else
        return false
        #endif
    }
    static var screen: String {
        ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--screen=") })?.replacingOccurrences(of: "--screen=", with: "") ?? "today"
    }
    static var tab: Int {
        switch screen { case "diary": return 1; case "income": return 2; case "settings": return 3; default: return 0 }
    }
    @MainActor static func prepare(store: PivotStore, calendar: CalendarService) {
        #if DEBUG && targetEnvironment(simulator)
        guard enabled else { return }
        let now = Date()
        func at(_ hour: Int, _ minute: Int = 0) -> Date { PivotDate.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)! }
        func item(_ id: String, _ title: String, _ kind: EventKind, _ start: Date, _ minutes: Int, _ color: String, _ notes: String = "") -> CalendarItem {
            .init(id: id, eventIdentifier: id, calendarIdentifier: "preview", calendarTitle: "Esempio", title: title, start: start, end: start.addingTimeInterval(Double(minutes) * 60), location: "", notes: notes, colorHex: color, isAllDay: false, writable: false, kind: kind)
        }
        let events = [item("breakfast", "Colazione con calma", .meal, at(9), 30, "F7C783"), item("gym", "Palestra", .workout, at(10), 120, "93B7FF"), item("lunch", "Pranzo", .meal, at(13), 60, "F7C783"), item("study", "Studio stechiometria", .study, now.addingTimeInterval(-600), 90, "7EE6CD", "40 minuti: unità di misura e conversioni.\n\nPausa di 10 minuti.\n\n40 minuti: mole e massa molare, con esercizi guidati. Segna gli errori su cui tornare domani.")]
        calendar.loadPreview(events)
        store.change { data in
            data = AppData()
            var breakfast = EventRecord(id: events[0].id, snapshot: events[0]); breakfast.status = .completed; breakfast.activeMinutes = 25
            var gym = EventRecord(id: events[1].id, snapshot: events[1]); gym.status = .partial; gym.activeMinutes = 75; gym.reason = "Avevo meno tempo: ho completato la prima parte."; gym.notes = "Buona energia durante gli esercizi."
            var study = EventRecord(id: events[3].id, snapshot: events[3]); study.status = .running; study.actualStart = now.addingTimeInterval(-600); study.activeMinutes = 10
            data.records = [breakfast.id: breakfast, gym.id: gym, study.id: study]
            var check = DayCheckIn(id: PivotDate.key(now)); check.wakeTime = at(8, 30); check.energyMorning = 7; check.moodMorning = 6
            data.checkIns[check.id] = check
            let a = Client(name: "Studente A", rateCents: 1800), b = Client(name: "Studente B", rateCents: 2000)
            data.clients = [a, b]
            let paid = IncomeEntry(clientID: a.id, clientName: a.name, date: now, minutes: 90, amountCents: 2700, paidCents: 2700, notes: "")
            let unpaid = IncomeEntry(clientID: b.id, clientName: b.name, date: now, minutes: 60, amountCents: 2000, paidCents: 0, notes: "")
            data.income = [paid, unpaid]
            data.payments = [.init(incomeID: paid.id, clientName: a.name, date: now, amountCents: 2700)]
        }
        #endif
    }
}
