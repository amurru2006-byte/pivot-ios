import SwiftUI

struct LessonLogisticsView: View {
    @EnvironmentObject var store: PivotStore
    @EnvironmentObject var calendar: CalendarService
    @Environment(\.dismiss) var dismiss
    let event: CalendarItem
    var onDefer: (() -> Void)? = nil
    @State private var logistics = LessonLogistics(studentName: "", place: .undecided)
    @State private var loaded = false
    var body: some View {
        NavigationStack {
            PivotScreen {
                PivotHeader(title: "Dove fai la lezione?", subtitle: "\(PivotDate.shortDate(event.start)) · \(PivotDate.time(event.start))–\(PivotDate.time(event.end))")
                PivotCard {
                    Text(event.title).font(.headline)
                    TextField("Conferma il nome dello studente", text: $logistics.studentName)
                    Button("Proponi l'ultima scelta di questo studente") { applyLastChoice() }.font(.caption)
                    Picker("Chi si sposta?", selection: $logistics.place) {
                        ForEach(LessonPlace.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    TextField("Indirizzo / luogo (facoltativo)", text: $logistics.address)
                    DurationField(title: "Viaggio per arrivare", seconds: Binding(get: { logistics.travelBeforeMinutes * 60 }, set: { logistics.travelBeforeMinutes = ($0 ?? 0) / 60 }), maxHours: 4)
                    DurationField(title: "Viaggio dopo la lezione", seconds: Binding(get: { logistics.travelAfterMinutes * 60 }, set: { logistics.travelAfterMinutes = ($0 ?? 0) / 60 }), maxHours: 4)
                    Toggle("Ho verificato i tempi di viaggio", isOn: $logistics.travelConfirmed)
                    Text("Conferma anche se il viaggio è zero. Non inventiamo un tragitto da un indirizzo incompleto.").font(.caption).foregroundStyle(PivotTheme.muted)
                    if logistics.travelConfirmed {
                        Text("Parti alle \(PivotDate.time(event.start.addingTimeInterval(-Double(logistics.travelBeforeMinutes) * 60)))").foregroundStyle(PivotTheme.accent)
                    }
                }
                Text("La scelta vale solo per questa lezione. Sarà proposta, non confermata automaticamente, la prossima volta.").font(.caption).foregroundStyle(PivotTheme.muted)
                Button("Conferma questa lezione") { save() }.buttonStyle(PivotPrimaryButton()).disabled(store.locked || logistics.studentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Più tardi") { onDefer?(); dismiss() }.buttonStyle(PivotSecondaryButton())
            }.navigationTitle("Ripetizioni")
                .onAppear {
                    guard !loaded else { return }
                    if let current = store.record(for: event).logistics, current.isConfirmed(for: event) { logistics = current }
                    else {
                        logistics.studentName = LessonLogistics.suggestedName(event, clients: store.data.clients)
                        applyLastChoice()
                        if !event.location.isEmpty { logistics.address = event.location }
                    }
                    loaded = true
                }
                .onChange(of: logistics.place) { _, _ in logistics.travelConfirmed = false }
        }.interactiveDismissDisabled(onDefer != nil)
    }
    private func applyLastChoice() {
        let name = logistics.studentName
        if let previous = store.data.lessonDefaults?[LessonLogistics.key(name)] {
            logistics = previous; logistics.studentName = name; logistics.confirmedAt = nil; logistics.travelConfirmed = false
        }
    }
    private func save() {
        guard let current = Planner.effectiveEvents(calendar.events, data: store.data).first(where: { $0.id == event.id }) else {
            store.error = "Questa lezione è stata cancellata o è cambiata. Aggiorna il calendario."; return
        }
        logistics.studentName = logistics.studentName.trimmingCharacters(in: .whitespacesAndNewlines)
        logistics.confirmedAt = Date()
        logistics.eventTitleAtConfirmation = current.title
        logistics.calendarLocationAtConfirmation = current.location
        var record = store.record(for: current); record.logistics = logistics; record.snapshot = current; record.updatedAt = Date()
        var rule = store.rule(for: current)
        rule.travelBeforeMinutes = logistics.travelBeforeMinutes; rule.travelAfterMinutes = logistics.travelAfterMinutes; rule.travelConfirmed = logistics.travelConfirmed
        if store.change({ data in
            data.records[current.id] = record; data.rules[current.id] = rule
            var defaults = data.lessonDefaults ?? [:]; defaults[LessonLogistics.key(logistics.studentName)] = logistics; data.lessonDefaults = defaults
        }) { dismiss() }
    }
}
