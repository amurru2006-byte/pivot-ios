import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: PivotStore
    @EnvironmentObject var calendar: CalendarService
    @State private var day = Date()
    var effective: [CalendarItem] { Planner.effectiveEvents(calendar.events, data: store.data) }
    var items: [CalendarItem] { effective.filter { PivotDate.calendar.isDate($0.start, inSameDayAs: day) }.sorted { $0.start < $1.start } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Giornata", selection: $day, displayedComponents: .date)
                    if store.locked { Text("Storico protetto: ripristina un backup nelle impostazioni prima di registrare altre attività.").foregroundStyle(.orange) }
                    if store.lastExternalBackup == nil {
                        Text("Prima di iniziare: configura un backup esterno in Impostazioni.").foregroundStyle(.orange)
                    }
                    NavigationLink("Sveglia, energia e umore") { DayCheckInView(day: day, initial: store.data.checkIns[PivotDate.key(day)]) }
                }
                if !calendar.hasAccess {
                    Section("Collega i calendari dell'iPhone") {
                        Text("Pivot legge gli eventi presenti nell'app Calendario, compresi gli account Google sincronizzati. Festività escluse.")
                        Button("Consenti accesso al calendario") {
                            Task { await calendar.requestAccess(); calendar.refresh(settings: store.data.settings) }
                        }
                        if let error = calendar.error { Text(error).foregroundStyle(.orange) }
                    }
                }
                if PivotDate.calendar.isDateInToday(day), let preferred = Planner.preferredEvent(items, data: store.data, now: Date()) {
                    Section("Adesso / appena terminato") {
                        NavigationLink { detail(preferred) } label: { EventRow(event: preferred, record: store.data.records[preferred.id]) }
                    }
                }
                Section("La giornata") {
                    if items.isEmpty { Text("Nessun evento. Controlla i calendari selezionati o aggiorna la giornata.").foregroundStyle(.secondary) }
                    ForEach(items) { event in
                        NavigationLink { detail(event) } label: { EventRow(event: event, record: store.data.records[event.id]) }
                    }
                }
                Section("Consiglio") {
                    Text(Planner.isStudyPriority(store.data, now: Date()) ? "Studio prioritario: se non puoi recuperare le ore prima dell'esame, non sacrificarle per la palestra. Gli impegni fissi restano protetti." : "Se salta un'attività, aprila e cerca uno spazio per recuperarla. Prima verifica i tempi di tragitto.")
                }
            }
            .navigationTitle("Pivot")
            .toolbar { Button { calendar.refresh(settings: store.data.settings) } label: { Image(systemName: "arrow.clockwise") } }
            .refreshable { calendar.refresh(settings: store.data.settings) }
        }
    }
    private func detail(_ event: CalendarItem) -> some View {
        EventDetailView(event: event, initial: store.record(for: event), rule: store.rule(for: event))
    }
}

struct DayCheckInView: View {
    @EnvironmentObject var store: PivotStore
    let day: Date
    @State private var check: DayCheckIn
    @State private var wake: Date
    @Environment(\.dismiss) var dismiss
    init(day: Date, initial: DayCheckIn?) {
        self.day = day
        _check = State(initialValue: initial ?? .init(id: PivotDate.key(day)))
        _wake = State(initialValue: initial?.wakeTime ?? PivotDate.calendar.date(bySettingHour: 7, minute: 45, second: 0, of: day)!)
    }
    var body: some View {
        Form {
            Section("Mattina") {
                DatePicker("Sveglia reale", selection: $wake, displayedComponents: .hourAndMinute)
                Text("Attuale registrazione: \(check.wakeTime.map(PivotDate.time) ?? "non indicata")").font(.caption)
                Button("Registra questo orario") { check.wakeTime = wake }
                RatingField(title: "Energia", value: $check.energyMorning)
                RatingField(title: "Umore", value: $check.moodMorning)
            }
            Section("Sera") {
                RatingField(title: "Energia", value: $check.energyEvening)
                RatingField(title: "Umore", value: $check.moodEvening)
            }
            Section("Note") { TextEditor(text: $check.notes).frame(minHeight: 100) }
            Button("Salva") { if store.change({ $0.checkIns[check.id] = check }) { dismiss() } }
        }.navigationTitle("Come stai?")
    }
}
