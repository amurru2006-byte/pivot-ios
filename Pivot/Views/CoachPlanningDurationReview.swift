import SwiftUI

/// The user binds a plan/day explicitly. No title guessing, automatic duration
/// change, health prompt or online request is involved in this local review.
struct CoachPlanningDurationReview: View {
    let sessionID: UUID
    let source: CalendarItem
    @EnvironmentObject private var store: PivotStore
    @EnvironmentObject private var calendar: CalendarService
    @State private var planID: UUID?
    @State private var dayID: String?
    @State private var candidate: CoachPlanningDurationChoice?
    @State private var problem: String?
    @State private var busy = false
    @State private var task: Task<Void, Never>?
    private var library: TrainingLibrary { store.data.training ?? TrainingLibrary() }
    private var session: CoachPlanningSession? { store.data.coachState.planningSessions?.first { $0.id == sessionID } }
    private var saved: CoachPlanningDurationChoice? { session?.durationChoices?.first { $0.sourceID == source.id } }

    var body: some View {
        DisclosureGroup("Durata personale · " + source.title) {
            Text("Calendario: \(Int(ceil(source.end.timeIntervalSince(source.start) / 60))) min. Scegli tu quale giorno della scheda corrisponde a questa attività.")
                .font(.caption)
            if let saved {
                Text("Durata adottata nel piano: \(saved.activityMinutes) min · \(saved.sampleIDs.count) sedute confrontabili")
                    .accessibilityIdentifier("coach-planning-duration-saved")
                Button("Torna alla durata del Calendario") { remove() }.frame(minHeight: 44)
                    .disabled(busy || store.locked).accessibilityIdentifier("coach-planning-duration-clear")
            }
            Picker("Scheda", selection: $planID) {
                Text("Scegli una scheda").tag(Optional<UUID>.none)
                ForEach(library.plans) { plan in Text(plan.payload.name).tag(Optional(plan.id)) }
            }.accessibilityIdentifier("coach-planning-duration-plan")
            if let planID, let plan = library.plans.first(where: { $0.id == planID }) {
                Picker("Giorno della scheda", selection: $dayID) {
                    Text("Scegli il giorno").tag(Optional<String>.none)
                    ForEach(plan.payload.days) { day in Text(day.name).tag(Optional(day.id)) }
                }.accessibilityIdentifier("coach-planning-duration-day")
            }
            Button("Calcola stima locale") { calculate() }.frame(minHeight: 44)
                .disabled(busy || store.locked || planID == nil || dayID == nil)
                .accessibilityIdentifier("coach-planning-duration-estimate")
            if busy { ProgressView("Confronto le sedute complete…") }
            if let candidate {
                Text("Mediana osservata: \(candidate.observedMedianMinutes) min · \(candidate.sampleIDs.count) sedute. Per cercare spazio userò \(candidate.activityMinutes) min, senza accorciare l’evento.")
                    .accessibilityIdentifier("coach-planning-duration-preview")
                Text(candidate.provisional ? "Stima provvisoria: pochi campioni confrontabili." : "Stima prudente dalle durate osservate, non una garanzia.").font(.caption)
                Text("Preparazione e tragitti restano da confermare separatamente. Questa scelta riguarda il piano; il Calendario non cambia ora.").font(.caption)
                Button("Usa \(candidate.activityMinutes) minuti nel piano") { save(candidate) }.frame(minHeight: 44)
                    .disabled(busy || store.locked).accessibilityIdentifier("coach-planning-duration-adopt")
            }
            if let problem { Text(problem).font(.caption).foregroundStyle(PivotTheme.amber) }
        }
        .onChange(of: planID) { _, _ in dayID = nil; invalidate() }
        .onChange(of: dayID) { _, _ in invalidate() }
        .onChange(of: store.data.updatedAt) { _, _ in invalidate() }
        .onChange(of: calendar.events) { _, _ in invalidate() }
        .onDisappear { task?.cancel() }
    }
    private func invalidate() { task?.cancel(); busy = false; candidate = nil; problem = nil }
    private func calculate() {
        guard !busy, !store.locked, !store.isRestoring, let planID, let dayID else { return }
        let library = library, revision = store.data.updatedAt, events = calendar.events, now = Date()
        busy = true; problem = nil; candidate = nil
        task = Task { @MainActor in
            do {
                let worker = Task.detached(priority: .userInitiated) {
                    try CoachPlanningDurationChoice.make(source: source, planID: planID, dayID: dayID, library: library, now: now)
                }
                let value = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled, revision == store.data.updatedAt, events == calendar.events, !store.locked else { return }
                busy = false; candidate = value
            } catch { guard !Task.isCancelled else { return }; busy = false; problem = error.localizedDescription }
        }
    }
    private func save(_ value: CoachPlanningDurationChoice) {
        guard !store.locked, !store.isRestoring, !busy, calendar.hasAccess, var next = session else { return }
        do {
            let now = Date()
            _ = try next.boundEvents(in: calendar.events, now: now)
            try value.revalidated(source: source, library: library, now: now)
            next.durationChoices = (next.durationChoices ?? []).filter { $0.sourceID != source.id } + [value]
            next.updatedAt = now
            try CoachPlanningLogistics.verify(next, events: calendar.events, data: store.data, now: now)
            var state = store.data.coachState; try CoachPlanningStore.save(next, in: &state)
            guard store.change({ $0.coachState = state }) else { problem = "Non riesco a salvare la durata."; return }
            candidate = nil
            task = Task { @MainActor in
                if !(await store.flushPendingWrites()) { problem = "Durata ancora in memoria: salvataggio su disco non riuscito. Tieni Pivot aperto e riprova il salvataggio." }
            }
        } catch { problem = error.localizedDescription }
    }
    private func remove() {
        guard !store.locked, !store.isRestoring, !busy, var next = session else { return }
        do {
            next.durationChoices?.removeAll { $0.sourceID == source.id }; next.updatedAt = Date()
            guard next.isActive(at: next.updatedAt) else { throw CoachPlanningSession.Failure.expired }
            var state = store.data.coachState; try CoachPlanningStore.save(next, in: &state)
            guard store.change({ $0.coachState = state }) else { problem = "Non riesco a salvare la modifica."; return }
        } catch { problem = error.localizedDescription }
    }
}
