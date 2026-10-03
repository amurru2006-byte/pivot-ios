import Foundation

enum Report {
    static func day(_ date: Date, events: [CalendarItem], data: AppData) -> String {
        let key = PivotDate.key(date)
        let items = Planner.plannedEvents(events, data: data).filter { $0.occurs(on: date) && !$0.isAllDay }
        var lines = ["PIVOT — Resoconto \(key)"]
        if let check = data.checkIns[key] {
            lines += ["Sveglia reale: \(check.wakeTime.map(PivotDate.time) ?? "non registrata")",
                      "Energia mattina/sera: \(check.energyMorning.map(String.init) ?? "—") / \(check.energyEvening.map(String.init) ?? "—")",
                      "Umore mattina/sera: \(check.moodMorning.map(String.init) ?? "—") / \(check.moodEvening.map(String.init) ?? "—")",
                      "Note giornata: \(check.notes)"]
            if let sleep = check.sleep {
                if let bedtime = sleep.bedtime { lines.append("A letto: \(PivotDate.shortDate(bedtime)) \(PivotDate.time(bedtime))") }
                if let duration = sleep.durationSeconds { lines.append("Tempo dormito (Apple Watch): \(ActivityTiming.duration(duration))") }
                if let score = sleep.score { lines.append("Punteggio sonno: \(score)/100") }
                if !sleep.quality.isEmpty { lines.append("Qualità sonno: \(sleep.quality)") }
                if let awakenings = sleep.awakenings { lines.append("Risvegli: \(awakenings)") }
                if let duration = sleep.interruptionSeconds { lines.append("Interruzioni: \(ActivityTiming.duration(duration))") }
            }
        } else { lines.append("Mancano sveglia reale, energia e umore.") }
        if Planner.universityAttendance(on: date, events: events, data: data) == false {
            lines.append("Lezioni universitarie: non previste oggi, per scelta esplicita. Gli esami restano in programma.")
        }
        var missing = 0
        for event in items.sorted(by: { $0.start < $1.start }) {
            let record = data.records[event.id]
            if record == nil || record?.status == .pending { missing += 1 }
            lines.append("\n\(PivotDate.time(event.start))–\(PivotDate.time(event.end)) \(event.title): \(record?.status.label ?? "Da compilare")")
            if let r = record {
                if let start = r.actualStart { lines.append("Inizio reale: \(PivotDate.time(start))") }
                if let end = r.actualEnd { lines.append("Fine reale: \(PivotDate.time(end))") }
                lines.append("Tempo registrato: \(r.activeMinutes) minuti")
                if !r.reason.isEmpty { lines.append("Motivo: \(r.reason)") }
                if !r.notes.isEmpty { lines.append("Note: \(r.notes)") }
                if let reminders = r.reminders, !reminders.isEmpty { lines.append("Promemoria dell'evento: \(reminders)") }
                if let logistics = r.logistics {
                    lines.append("Lezione con \(logistics.studentName): \(logistics.place.label) · \(logistics.address)")
                }
                if let cardio = r.cardio {
                    lines.append("Cardio: \(cardio.kind.label)")
                    if let duration = cardio.durationSeconds { lines.append("Durata allenamento: \(ActivityTiming.duration(duration))") }
                    if let distance = cardio.distanceKM { lines.append("Distanza: \(distance) km") }
                    if let calories = cardio.activeCalories { lines.append("Calorie attive: \(calories) kcal") }
                    if let calories = cardio.totalCalories { lines.append("Calorie totali: \(calories) kcal") }
                    if let elevation = cardio.elevationM { lines.append("Dislivello: \(elevation) m") }
                    if let bpm = cardio.averageBPM { lines.append("Battito medio: \(bpm) bpm") }
                    if let effort = cardio.effort { lines.append("Sforzo: \(effort)/10") }
                    if let speed = cardio.speedKMH { lines.append("Velocità tapis roulant: \(speed) km/h") }
                    if let incline = cardio.inclinePercent { lines.append("Inclinazione tapis roulant: \(incline)%") }
                    if let pace = cardio.paceSecondsPerKM { lines.append("Ritmo medio per km: \(ActivityTiming.duration(pace))") }
                    if !cardio.notes.isEmpty { lines.append("Note cardio: \(cardio.notes)") }
                }
                if let study = r.study {
                    if !study.objectives.isEmpty { lines.append("Obiettivi della sessione: \(study.objectives)") }
                    if !study.exercises.isEmpty { lines.append("Esercizi previsti: \(study.exercises)") }
                    if !study.documents.isEmpty { lines.append("Materiali PDF: \(study.documents.map(\.name).joined(separator: ", "))") }
                }
                if let details = r.reflection {
                    if !details.focus.isEmpty { lines.append("Attività svolta: \(details.focus)") }
                    if !details.result.isEmpty { lines.append("Risultato: \(details.result)") }
                    if !details.nextStep.isEmpty { lines.append("Prossimo passo: \(details.nextStep)") }
                }
                if [.tutoring, .work].contains(event.kind) && [.completed, .partial].contains(r.status) && r.tutoringAnswered != true && r.incomeID == nil {
                    missing += 1; lines.append("Manca il compenso della ripetizione.")
                }
                if event.kind == .meal {
                    lines.append("Fame prima/dopo: \(r.hungerBefore.map(String.init) ?? "—") / \(r.hungerAfter.map(String.init) ?? "—")")
                    lines.append("Piano alimentare rispettato: \(r.followedMeal.map { $0 ? "sì" : "no" } ?? "non indicato")")
                }
            }
        }
        for session in (data.training?.sessions ?? []).filter({ PivotDate.calendar.isDate($0.start, inSameDayAs: date) }) {
            lines.append("\n" + TrainingExport.text(session, library: data.training ?? TrainingLibrary()))
        }
        let entries = data.income.filter { PivotDate.calendar.isDate($0.date, inSameDayAs: date) }
        let payments = data.payments.filter { PivotDate.calendar.isDate($0.date, inSameDayAs: date) }
        lines.append("\nIncassato oggi: \(Money.display(payments.reduce(0) { $0 + $1.amountCents }))")
        lines.append("Da incassare per queste lezioni: \(Money.display(entries.reduce(0) { $0 + $1.outstandingCents }))")
        let coachMessages = (data.coach?.messages ?? []).filter { $0.dayKey == key }
        if !coachMessages.isEmpty {
            lines.append("\nConversazione con Pivot Coach")
            for message in coachMessages {
                let speaker = message.role == .user ? "Tu" : (message.role == .coach ? "Coach" : "Decisione")
                lines.append("\(speaker): \(message.text)")
            }
        }
        let pending = (data.coach?.pendingCalendarChanges ?? []).filter { PivotDate.key($0.move.proposedStart) == key || PivotDate.key($0.move.source.start) == key }
        if !pending.isEmpty { lines.append("Modifiche locali ancora da confermare nel Calendario: \(pending.count).") }
        lines.append("\nEventi da compilare: \(missing).")
        lines.append("Invia questo testo a ChatGPT per una valutazione più ampia. Pivot Coach usa regole locali prudenti e non modifica il Calendario senza conferma finale.")
        return lines.joined(separator: "\n")
    }
}
