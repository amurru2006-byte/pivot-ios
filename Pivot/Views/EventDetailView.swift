import SwiftUI

struct EventDetailView: View {
    @EnvironmentObject var store: PivotStore
    @EnvironmentObject var calendar: CalendarService
    let event: CalendarItem
    @State private var record: EventRecord
    @State private var rule: EventRule
    @State private var message: String?
    @State private var suggestions: [RecoverySuggestion] = []
    @State private var pendingMove: PlanMove?
    @State private var calendarApproval = false
    @Environment(\.dismiss) private var dismiss

    init(event: CalendarItem, initial: EventRecord, rule: EventRule) {
        self.event = event
        _record = State(initialValue: initial)
        _rule = State(initialValue: rule)
    }
    var body: some View {
        Form {
            Section {
                Text(event.title).font(.title2.bold())
                Text("\(PivotDate.time(event.start)) – \(PivotDate.time(event.end)) · \(event.calendarTitle)")
                if !event.location.isEmpty { Text(event.location) }
                if !event.notes.isEmpty { Text(event.notes).font(.callout).textSelection(.enabled) }
            }
            Section("Registrazione") {
                Text("Stato: \(record.status.label)")
                if let start = record.actualStart { Text("Inizio reale: \(PivotDate.time(start))") }
                if let end = record.actualEnd { Text("Fine reale: \(PivotDate.time(end))") }
                Button(record.status == .running ? "Termina" : "Inizia") {
                    if record.status == .running { record.actualEnd = Date(); record.status = .completed; updateMinutes() }
                    else { record.actualStart = Date(); record.actualEnd = nil; record.status = .running }
                    save()
                }.disabled(event.isAllDay || store.locked)
                Picker("Esito", selection: $record.status) {
                    ForEach(Completion.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Stepper("Tempo registrato: \(record.activeMinutes) min", value: $record.activeMinutes, in: 0...1440, step: 5)
                Text("Il pulsante misura il tempo trascorso. Correggilo se ci sono state pause.").font(.caption).foregroundStyle(.secondary)
                if record.status == .partial || record.status == .skipped {
                    TextField("Perché? Cosa ti ha fermato?", text: $record.reason, axis: .vertical)
                }
                TextField("Note extra", text: $record.notes, axis: .vertical).lineLimit(3...8)
                RatingField(title: "Energia", value: $record.energy)
            }
            if event.kind == .meal {
                Section("Pasto") {
                    RatingField(title: "Fame prima", value: $record.hungerBefore)
                    RatingField(title: "Fame dopo", value: $record.hungerAfter)
                    Picker("Piano rispettato", selection: Binding(get: { record.followedMeal.map { $0 ? 1 : 2 } ?? 0 }, set: { record.followedMeal = $0 == 0 ? nil : $0 == 1 })) {
                        Text("Non indicato").tag(0); Text("Sì").tag(1); Text("No").tag(2)
                    }
                }
            }
            Section("Regole e tragitto") {
                Picker("Gestione", selection: $rule.flexibility) {
                    ForEach(EventFlexibility.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Stepper("Minimo: \(rule.minimumMinutes) min", value: $rule.minimumMinutes, in: 5...300, step: 5)
                Stepper("Tragitto prima: \(rule.travelBeforeMinutes) min", value: $rule.travelBeforeMinutes, in: 0...240, step: 5)
                Stepper("Tragitto dopo: \(rule.travelAfterMinutes) min", value: $rule.travelAfterMinutes, in: 0...240, step: 5)
                Toggle("Ho verificato questi tempi (anche se zero)", isOn: $rule.travelConfirmed)
                Text("La durata dell'evento palestra include allenamento, cambio e doccia. Qui inserisci solo i tragitti. Nessuna riduzione o rinuncia è applicata automaticamente.").font(.caption)
            }
            Section {
                Button("Salva registrazione e regole") { save() }
                if rule.flexibility != .fixed && !event.isAllDay {
                    Button("Trova uno spazio per recuperare") {
                        guard rule.travelConfirmed else { message = "Prima conferma i tempi di tragitto. Non posso supporre che siano zero."; return }
                        guard save() else { return }
                        suggestions = Planner.recover(event, events: calendar.events, data: store.data, now: Date())
                        if suggestions.isEmpty { message = "Nessuna proposta sicura nei prossimi tre giorni. Controlla i tragitti degli altri eventi fuori casa, oppure la disponibilità di uno spazio completo. Non ho tagliato altri eventi. Confrontiamoci su cosa puoi accorciare o rimandare; lo studio si riduce solo se recuperabile." }
                    }
                }
            }
            ForEach(suggestions) { suggestion in
                Section("\(PivotDate.key(suggestion.start)) · \(PivotDate.time(suggestion.start))–\(PivotDate.time(suggestion.end))") {
                    Text(suggestion.explanation)
                    Button("Usa questo spazio solo in Pivot") { choose(suggestion, sync: false) }
                    Button("Approva modifica anche nel Calendario") { choose(suggestion, sync: true) }.disabled(!event.writable)
                }
            }
            if let message { Text(message).foregroundStyle(.orange) }
        }
        .navigationTitle("Attività")
        .alert("Modificare il Calendario?", isPresented: $calendarApproval) {
            Button("Annulla", role: .cancel) { pendingMove = nil }
            Button("Confermo la modifica") { applyApprovedMove() }
        } message: {
            if let move = pendingMove {
                Text("\(event.title)\nDa: \(PivotDate.key(move.source.start)) \(PivotDate.time(move.source.start))–\(PivotDate.time(move.source.end))\nA: \(PivotDate.key(move.proposedStart)) \(PivotDate.time(move.proposedStart))–\(PivotDate.time(move.proposedEnd))\nSi modifica solo questa occorrenza. La modifica si sincronizza agli altri dispositivi.")
            }
        }
    }
    private func updateMinutes() {
        if let start = record.actualStart, let end = record.actualEnd { record.activeMinutes = max(0, Int(end.timeIntervalSince(start) / 60)) }
    }
    @discardableResult private func save() -> Bool {
        if (record.status == .partial || record.status == .skipped) && record.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message = "Scrivi il motivo dell'attività parziale o saltata."; return false
        }
        record.updatedAt = Date()
        return store.change { data in data.records[event.id] = record; data.rules[event.id] = rule }
    }
    private func choose(_ suggestion: RecoverySuggestion, sync: Bool) {
        calendar.refresh(settings: store.data.settings)
        guard let source = calendar.events.first(where: { $0.id == event.id }) else {
            message = "L'evento è cambiato o non è più disponibile. Aggiorna la giornata."; return
        }
        let move = PlanMove(source: source, proposedStart: suggestion.start, proposedEnd: suggestion.end)
        guard slotIsAvailable(move) else { message = "Questo spazio non è più libero. Cerca una nuova proposta."; return }
        if sync { pendingMove = move; calendarApproval = true }
        else {
            if store.change({ $0.moves.append(move) }) { message = "Proposta approvata solo in Pivot. Il Calendario non è cambiato."; suggestions = [] }
        }
    }
    private func applyApprovedMove() {
        guard var move = pendingMove else { return }
        guard !store.locked else { message = "Lo storico è bloccato: ripristina il backup prima di modificare eventi."; return }
        do {
            // Validate the chosen slot against a fresh calendar view before writing.
            calendar.refresh(settings: store.data.settings)
            guard slotIsAvailable(move) else { message = "Questo spazio non è più libero. Cerca una nuova proposta."; return }
            try calendar.apply(move)
            move.syncedToCalendar = true
            if !store.change({ $0.moves.append(move) }) {
                message = "Il Calendario è stato modificato, ma lo storico locale non è stato salvato. Controlla la copia di backup."; return
            }
            calendar.refresh(settings: store.data.settings)
            message = "Evento aggiornato nel Calendario. Solo questa occorrenza."
            suggestions = []
        } catch { message = error.localizedDescription }
        pendingMove = nil
    }
    private func slotIsAvailable(_ move: PlanMove) -> Bool {
        guard rule.travelConfirmed, move.proposedStart > Date() else { return false }
        let occupiedStart = move.proposedStart.addingTimeInterval(-Double(rule.travelBeforeMinutes) * 60)
        let occupiedEnd = move.proposedEnd.addingTimeInterval(Double(rule.travelAfterMinutes) * 60)
        return !Planner.effectiveEvents(calendar.events, data: store.data).contains { item in
            guard item.id != event.id, !item.isAllDay else { return false }
            let other = store.rule(for: item)
            if !item.location.isEmpty && !other.travelConfirmed && PivotDate.key(item.start) == PivotDate.key(move.proposedStart) { return true }
            return item.start.addingTimeInterval(-Double(other.travelBeforeMinutes) * 60) < occupiedEnd
                && item.end.addingTimeInterval(Double(other.travelAfterMinutes) * 60) > occupiedStart
        }
    }
}
