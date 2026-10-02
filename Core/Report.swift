import Foundation

enum Report {
    static func day(_ date: Date, events: [CalendarItem], data: AppData) -> String {
        let key = PivotDate.key(date)
        let items = events.filter { PivotDate.calendar.isDate($0.start, inSameDayAs: date) && !$0.isAllDay }
        var lines = ["PIVOT — Resoconto \(key)"]
        if let check = data.checkIns[key] {
            lines += ["Sveglia reale: \(check.wakeTime.map(PivotDate.time) ?? "non registrata")",
                      "Energia mattina/sera: \(check.energyMorning.map(String.init) ?? "—") / \(check.energyEvening.map(String.init) ?? "—")",
                      "Umore mattina/sera: \(check.moodMorning.map(String.init) ?? "—") / \(check.moodEvening.map(String.init) ?? "—")",
                      "Note giornata: \(check.notes)"]
        } else { lines.append("Mancano sveglia reale, energia e umore.") }
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
                if event.kind == .meal {
                    lines.append("Fame prima/dopo: \(r.hungerBefore.map(String.init) ?? "—") / \(r.hungerAfter.map(String.init) ?? "—")")
                    lines.append("Piano alimentare rispettato: \(r.followedMeal.map { $0 ? "sì" : "no" } ?? "non indicato")")
                }
            }
        }
        let entries = data.income.filter { PivotDate.calendar.isDate($0.date, inSameDayAs: date) }
        let payments = data.payments.filter { PivotDate.calendar.isDate($0.date, inSameDayAs: date) }
        lines.append("\nIncassato oggi: \(Money.display(payments.reduce(0) { $0 + $1.amountCents }))")
        lines.append("Da incassare per queste lezioni: \(Money.display(entries.reduce(0) { $0 + $1.outstandingCents }))")
        lines.append("\nEventi da compilare: \(missing).")
        lines.append("Invia questo testo a ChatGPT per la valutazione. Pivot usa regole locali, non un'IA collegata automaticamente alla chat.")
        return lines.joined(separator: "\n")
    }
}
