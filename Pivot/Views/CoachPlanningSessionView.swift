import SwiftUI

struct CoachPlanningSessionView: View {
    let sessionID: UUID
    @EnvironmentObject private var store: PivotStore
    @EnvironmentObject private var calendar: CalendarService
    @State private var preparationIncluded = false
    @State private var options: [CoachOption] = []
    @State private var reviewed: Set<UUID> = []
    @State private var message: String?
    @State private var planning = false
    @State private var task: Task<Void, Never>?
    private var session: CoachPlanningSession? { store.data.coachState.planningSessions?.first { $0.id == sessionID } }

    var body: some View {
        PivotScreen {
            PivotHeader(title: "Il tuo piano", subtitle: "Controlliamo gli spazi reali. Il Calendario cambia soltanto dopo la tua conferma.")
            if let session {
                PivotCard {
                    ForEach(Array(session.intent.eventIDs.enumerated()), id: \.offset) { index, alias in
                        if let source = session.bindings[alias] {
                            Text("\(index + 1). \(source.title)").font(.headline)
                            Text("\(PivotDate.shortDate(source.start)) · \(source.durationMinutes) min").font(.subheadline)
                            NavigationLink("Controlla attività e tragitti") {
                                EventDetailView(event: source, initial: store.record(for: source), rule: store.rule(for: source))
                            }.frame(minHeight: 44)
                        }
                    }
                    Text("Giorni: " + session.allowedDays.map(PivotDate.shortDate).joined(separator: ", "))
                        .accessibilityIdentifier("coach-planning-days")
                    if !session.excludedDays.isEmpty { Text("Esclusi: " + session.excludedDays.map(PivotDate.shortDate).joined(separator: ", ")) }
                    if let band = session.intent.band { Text("Fascia: " + band.label) }
                    if let minute = session.intent.earliestMinute { Text("Non prima delle \(minute / 60):\(String(format: "%02d", minute % 60))") }
                    if let minute = session.intent.latestMinute { Text("Entro le \(minute / 60):\(String(format: "%02d", minute % 60))") }
                    if let alias = session.intent.afterEventID, let reference = session.bindings[alias] { Text("Dopo: " + reference.title) }
                    if session.status == .staged {
                        Text("Alternativa preparata in Pivot. Restano le conferme finali per il Calendario.")
                        NavigationLink("Apri le conferme per il Calendario") { CoachView() }.frame(minHeight: 44)
                    } else if session.status == .dismissed {
                        Text("Piano archiviato. Nessun evento è stato cancellato.")
                    } else if !session.isActive(at: Date()) {
                        Text("La settimana di questo piano è terminata. Chiedi un nuovo piano: le date non vengono spostate automaticamente.")
                    } else if !session.pendingReadmittedDays.isEmpty {
                        Text("Questi giorni erano esclusi: " + session.pendingReadmittedDays.map(PivotDate.shortDate).joined(separator: ", "))
                            .foregroundStyle(PivotTheme.amber)
                        Button("Confermo di reincludere questi giorni") { readmit(session) }
                            .frame(minHeight: 44).disabled(store.locked).accessibilityIdentifier("coach-planning-readmit")
                    } else {
                        Toggle("Le durate comprendono cambio e preparazione necessari", isOn: $preparationIncluded)
                            .accessibilityIdentifier("coach-planning-preparation")
                        Button("Cerca alternative") { search(session) }.buttonStyle(PivotPrimaryButton())
                            .disabled(!preparationIncluded || planning || store.locked).accessibilityIdentifier("coach-planning-search")
                        if planning { ProgressView("Confronto giorni e tragitti…") }
                    }
                }
                if session.status == .draft {
                    Text("Per cambiare giorni, fascia o ordine torna nella chat e continua questo piano. I vincoli restano salvati; questa ricerca è locale e non usa token AI.")
                        .font(.caption).foregroundStyle(PivotTheme.muted)
                }
                ForEach(options) { option in
                    PivotCard(tint: PivotTheme.blue) {
                        Text(option.explanation).font(.headline)
                        Text(option.consequences).font(.subheadline).foregroundStyle(PivotTheme.muted)
                        ForEach(option.moves) { move in
                            if !move.source.location.isEmpty {
                                NavigationLink { TravelCalculatorView(destination: move.source.location, date: move.proposedStart, timing: .arriveBy,
                                    nextStart: move.proposedStart, context: .init(events: [move.source])) } label: {
                                    Label("Controlla tragitto: " + move.source.title, systemImage: "map")
                                }.frame(minHeight: 44)
                            }
                        }
                        Toggle("Confermo ordine, durate e tragitti per questi orari", isOn: Binding(get: { reviewed.contains(option.id) }, set: {
                            if $0 { reviewed.insert(option.id) } else { reviewed.remove(option.id) }
                        })).accessibilityIdentifier("coach-planning-route-review")
                        Button("Scegli questa alternativa in Pivot") { stage(option, session: session) }.buttonStyle(PivotPrimaryButton())
                            .disabled(store.locked || !reviewed.contains(option.id)).accessibilityIdentifier("coach-planning-stage")
                    }
                }
                if session.status == .draft {
                    Button("Archivia questo piano", role: .destructive) {
                        store.change { data in
                            if let index = data.coachState.planningSessions?.firstIndex(where: { $0.id == sessionID }) { data.coachState.planningSessions?[index].status = .dismissed }
                            if data.coachState.focusedPlanningSessionID == sessionID { data.coachState.focusedPlanningSessionID = nil }
                        }
                    }.frame(minHeight: 44).disabled(store.locked || planning)
                }
            } else { Text("Questo piano non è più disponibile.") }
            if let message { Text(message).foregroundStyle(PivotTheme.amber).accessibilityIdentifier("coach-planning-message") }
        }.navigationTitle("Piano di recupero")
            .onChange(of: preparationIncluded) { _, _ in invalidate() }
            .onChange(of: store.data.updatedAt) { _, _ in invalidate() }
            .onChange(of: calendar.events) { _, _ in invalidate() }
            .onDisappear { task?.cancel(); planning = false }
    }
    private func invalidate() { task?.cancel(); planning = false; options = []; reviewed = [] }
    private func readmit(_ value: CoachPlanningSession) {
        do {
            var next = value; try next.confirmReadmittedDays(now: Date())
            var state = store.data.coachState; try CoachPlanningStore.save(next, in: &state)
            store.change { $0.coachState = state }
        } catch { message = error.localizedDescription }
    }
    private func search(_ value: CoachPlanningSession) {
        invalidate(); message = nil; planning = true
        task = Task { @MainActor in
            guard !Task.isCancelled, !store.locked, !store.isRestoring else { planning = false; return }
            let data = store.data, events = calendar.events, access = calendar.hasAccess, now = Date()
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try CoachPlanningAlternatives.options(for: value, calendarAccess: access, events: events,
                        data: data, now: now, preparationIncluded: true)
                }.value
                guard !Task.isCancelled else { return }
                planning = false
                guard data.updatedAt == store.data.updatedAt, events == calendar.events, !store.locked else { message = "L’agenda è cambiata: ripeti la ricerca."; return }
                options = result
                if result.isEmpty { message = "Non ho trovato un’alternativa verificata. Controlla giorni, flessibilità e tragitti; questo non significa che l’agenda sia necessariamente piena." }
            } catch { guard !Task.isCancelled else { return }; planning = false; message = error.localizedDescription }
        }
    }
    private func stage(_ option: CoachOption, session: CoachPlanningSession) {
        guard !store.locked, !store.isRestoring else { return }
        var failure: String?
        let access = calendar.hasAccess, events = calendar.events, reviewed = reviewed.contains(option.id)
        let saved = store.change { data in
            do { try CoachPlanningAlternatives.stage(option, session: session, calendarAccess: access, events: events,
                data: &data, now: Date(), preparationIncluded: preparationIncluded, routesReviewed: reviewed) }
            catch { failure = error.localizedDescription }
        }
        message = saved ? failure ?? "Alternativa preparata. Apri le conferme per aggiornare il Calendario." : "Non riesco a salvare la proposta."
    }
}
