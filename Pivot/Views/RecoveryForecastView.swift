import SwiftUI

struct RecoveryForecastView: View {
    @EnvironmentObject private var store: PivotStore
    @EnvironmentObject private var calendar: CalendarService
    @State private var targetID: String?
    @State private var days = 7
    @State private var preferredBand: TrainingDurationTimeBand?
    @State private var preparationIncluded = false
    @State private var temporary = false
    @State private var until = Date().addingTimeInterval(7 * 86400)
    @State private var options: [CoachOption] = []
    @State private var reviewed: Set<UUID> = []
    @State private var message: String?
    @State private var planning = false
    @State private var didLoad = false
    @State private var staged = false
    @State private var task: Task<Void, Never>?
    private var candidates: [CalendarItem] {
        let now = Date()
        return EventCoalescer.unique(calendar.events, data: store.data).filter {
            $0.end <= now && $0.end >= now.addingTimeInterval(-14 * 86400) && !$0.isAllDay && $0.writable
                && [.pending, .skipped].contains(store.data.records[$0.id]?.status ?? .pending)
        }.sorted { $0.start > $1.start }
    }
    var body: some View {
        PivotScreen {
            PivotHeader(title: "Troviamo un’alternativa", subtitle: "Fino a 7 giorni, senza cambiare nulla finché non scegli.")
            PivotCard {
                if candidates.isEmpty { Text("Non ci sono attività passate da chiarire negli ultimi 14 giorni.").foregroundStyle(PivotTheme.muted) }
                Picker("Attività", selection: $targetID) {
                    Text("Scegli l’attività da recuperare").tag(String?.none)
                    ForEach(candidates) { Text("\($0.title) · \(PivotDate.shortDate($0.start))").tag(Optional($0.id)) }
                }.accessibilityIdentifier("prediction-recovery-target")
                if let target = candidates.first(where: { $0.id == targetID }) {
                    NavigationLink("Controlla attività e tragitti") {
                        EventDetailView(event: target, initial: store.record(for: target), rule: store.rule(for: target))
                    }.frame(minHeight: 44)
                }
                Stepper("Cerca nei prossimi \(days) giorni", value: $days, in: 1...7)
                Picker("Fascia per questo recupero", selection: $preferredBand) {
                    Text("Qualsiasi orario consentito").tag(TrainingDurationTimeBand?.none)
                    ForEach([TrainingDurationTimeBand.morning, .afternoon, .evening], id: \.self) { Text($0.label.capitalized).tag(Optional($0)) }
                }.accessibilityIdentifier("prediction-recovery-band")
                Toggle("La durata a calendario comprende cambio e preparazione necessari", isOn: $preparationIncluded)
                    .accessibilityIdentifier("prediction-recovery-preparation")
                if !preparationIncluded { Text("Se manca del tempo, correggi prima la durata nell’attività. Non considero cambio e preparazione pari a zero senza conferma.").font(.caption).foregroundStyle(PivotTheme.muted) }
                Button("Cerca alternative") { search() }.buttonStyle(PivotPrimaryButton())
                    .disabled(targetID == nil || !preparationIncluded || planning || store.locked).accessibilityIdentifier("prediction-recovery-search")
                if planning { ProgressView("Controllo calendario e tempi…") }
            }
            DisclosureGroup("Ricorda le mie preferenze") {
                Text("Solo le scelte che confermi: nessuna abitudine o limitazione medica viene dedotta. Puoi cambiarle per ogni ricerca.").font(.caption).foregroundStyle(PivotTheme.muted)
                Toggle("Preferenza temporanea", isOn: $temporary)
                if temporary { DatePicker("Valida fino a", selection: $until, in: Date()...) }
                Button("Ricorda giorni e fascia scelti") {
                    let value = RecoveryPlanningPreferences(horizonDays: days, preferredBand: preferredBand, expiresAt: temporary ? until : nil)
                    guard value.isValid else { message = "Controlla la scadenza della preferenza."; return }
                    if store.change({ $0.settings.recoveryPlanningPreferences = value }) { message = "Preferenze confermate, solo sul dispositivo e nel tuo backup." }
                }.frame(minHeight: 44).disabled(store.locked)
                if let value = store.data.settings.recoveryPlanningPreferences {
                    Text(value.isActive(at: Date()) ? "Preferenza confermata attiva" : "Preferenza scaduta: non viene applicata").font(.caption)
                    Button("Dimentica preferenza", role: .destructive) { store.change { $0.settings.recoveryPlanningPreferences = nil } }
                        .frame(minHeight: 44).disabled(store.locked)
                }
            }
            if let message { Text(message).font(.subheadline).foregroundStyle(PivotTheme.amber).accessibilityIdentifier("prediction-recovery-message") }
            ForEach(options) { option in
                PivotCard(tint: PivotTheme.blue) {
                    Text(option.explanation).font(.headline)
                    Text(option.consequences).font(.subheadline).foregroundStyle(PivotTheme.muted)
                    if let move = option.moves.first {
                        NavigationLink { TravelCalculatorView(destination: move.source.location, date: move.proposedStart, timing: .arriveBy,
                                                             nextStart: move.proposedStart, context: .init(events: [move.source])) } label: {
                            Label("Controlla il tragitto per questo orario", systemImage: "map")
                        }.frame(minHeight: 44)
                    }
                    Toggle("Confermo durata e tragitti per questo orario", isOn: Binding(get: { reviewed.contains(option.id) }, set: { value in
                        if value { reviewed.insert(option.id) } else { reviewed.remove(option.id) }
                    })).accessibilityIdentifier("prediction-recovery-review")
                    Button("Scegli questa alternativa in Pivot") { stage(option) }.buttonStyle(PivotPrimaryButton())
                        .disabled(store.locked || !reviewed.contains(option.id)).accessibilityIdentifier("prediction-recovery-stage")
                }
            }
            if staged { NavigationLink("Apri la conferma per il Calendario") { CoachView() }.buttonStyle(PivotSecondaryButton()).accessibilityIdentifier("prediction-recovery-open-coach") }
            Text("Nessuna durata di guarigione, cancellazione o spostamento delle altre sedute viene inventato. Una stima personale più lunga richiede di rivedere la durata dell’attività, non di accorciarla per farla entrare.")
                .font(.caption).foregroundStyle(PivotTheme.muted)
        }.navigationTitle("Alternative")
            .onAppear {
                guard !didLoad else { return }; didLoad = true
                if let value = store.data.settings.recoveryPlanningPreferences, value.isActive(at: Date()) {
                    days = value.horizonDays; preferredBand = value.preferredBand
                    temporary = value.expiresAt != nil; if let date = value.expiresAt { until = date }
                }
            }
            .onChange(of: targetID) { _, _ in preparationIncluded = false; invalidate() }
            .onChange(of: preparationIncluded) { _, _ in invalidate() }
            .onChange(of: days) { _, _ in invalidate() }
            .onChange(of: preferredBand) { _, _ in invalidate() }
            .onChange(of: store.data.updatedAt) { _, _ in invalidate() }
            .onChange(of: calendar.events) { _, _ in invalidate() }
            .onDisappear { task?.cancel(); planning = false }
    }
    private func invalidate() { task?.cancel(); planning = false; options = []; reviewed = [] }
    private func search() {
        guard let targetID else { return }
        let events = calendar.events, snapshot = store.data, now = Date(), count = days, band = preferredBand, included = preparationIncluded
        options = []; reviewed = []; message = nil; planning = true; staged = false
        task = Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                RecoveryForecast.options(targetID: targetID, events: events, data: snapshot, now: now, days: count, preferredBand: band, preparationIncluded: included)
            }.value
            guard !Task.isCancelled else { return }
            planning = false
            guard snapshot.updatedAt == store.data.updatedAt, events == calendar.events else { message = "L’agenda è cambiata: ripeti la ricerca."; return }
            options = result
            if result.isEmpty { message = "Non c’è un’alternativa verificata. Controlla flessibilità, tragitti dell’attività e degli altri impegni, eventi per l’intera giornata e fascia scelta." }
        }
    }
    private func stage(_ option: CoachOption) {
        guard reviewed.contains(option.id), !store.locked else { return }
        var snapshot = store.data
        if let problem = CoachPlanner.accept(option, events: calendar.events, data: &snapshot, now: Date()) { message = problem; invalidate(); return }
        if store.change({ $0 = snapshot }) { staged = true; options = []; reviewed = []; message = "Scelta salvata in Pivot. Il Calendario non è ancora cambiato: apri la conferma finale." }
    }
}
