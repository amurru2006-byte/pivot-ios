import SwiftUI

private struct TrainingForecastSummary: Identifiable {
    var planID: UUID
    var dayID: String
    var name: String
    var estimate: TrainingDurationEstimate?
    var quality: TrainingPredictionQuality
    var id: String { planID.uuidString + ":" + dayID }
}
private struct UpcomingJourney: Identifiable {
    var from: CalendarItem
    var to: CalendarItem
    var id: [String] { [from.id, to.id] }
}

struct PersonalForecastView: View {
    @EnvironmentObject private var store: PivotStore
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var agenda: AgendaService
    @State private var day: DayPlanningContext?
    @State private var durations: [TrainingForecastSummary] = []
    @State private var refreshedAt: Date?
    @State private var refreshID = UUID()
    private var refreshKey: String { "\(store.data.updatedAt)|\(agenda.revision)|\(refreshID)" }
    private var journeys: [UpcomingJourney] {
        let now = Date()
        let future = agenda.planned.filter { !$0.isAllDay && $0.end > now && $0.start < now.addingTimeInterval(7 * 86400) }
            .sorted { $0.start < $1.start }
        guard future.count > 1 else { return [] }
        return zip(future, future.dropFirst()).filter { !$0.0.location.isEmpty && !$0.1.location.isEmpty }.prefix(5)
            .map { .init(from: $0.0, to: $0.1) }
    }
    var body: some View {
        PivotScreen {
            PivotHeader(title: "Previsioni personali", subtitle: "Dati osservati, ipotesi dichiarate e decisioni tue.")
            dayCard
            NavigationLink { RecoveryForecastView() } label: {
                PivotCard { ActionRow(title: "Alternative su più giorni", subtitle: "Confronta gli spazi e conferma cosa recuperare", icon: "calendar.badge.clock") }
            }.buttonStyle(.plain).accessibilityIdentifier("prediction-recovery")
            NavigationLink { TravelCalculatorView() } label: {
                PivotCard { ActionRow(title: "Tragitti reali", subtitle: "Luoghi scelti da te · Apple Maps con consenso", icon: "map.fill") }
            }.buttonStyle(.plain).accessibilityIdentifier("prediction-travel")
            if !journeys.isEmpty {
                SectionHeading(title: "Da un impegno al successivo")
                ForEach(journeys) { journey in
                    NavigationLink {
                        TravelCalculatorView(origin: journey.from.location, destination: journey.to.location,
                                             date: max(journey.from.end, Date().addingTimeInterval(60)), timing: .departAt,
                                             nextStart: journey.to.start, context: .init(events: [journey.from, journey.to]))
                    } label: {
                        PivotCard {
                            ActionRow(title: "\(journey.from.title) → \(journey.to.title)",
                                      subtitle: "Partenza ipotizzata dal luogo del primo impegno · controlla se arrivi in tempo", icon: "arrow.triangle.branch")
                        }
                    }.buttonStyle(.plain)
                }
            }
            if !durations.isEmpty {
                SectionHeading(title: "Il tempo dei tuoi allenamenti")
                ForEach(durations) { value in
                    PivotCard {
                        Text(value.name).font(.headline)
                        if let estimate = value.estimate {
                            Text("\(estimate.activityMinutes) min · mediana personale").foregroundStyle(PivotTheme.accent)
                            if let stats = estimate.statistics { Text("Fascia osservata \(stats.lowerMinutes)–\(stats.upperMinutes) min · \(stats.count) sedute").font(.caption).foregroundStyle(PivotTheme.muted) }
                            if estimate.provisional { Text("Stima provvisoria: lo storico è ancora ridotto.").font(.caption).foregroundStyle(PivotTheme.muted) }
                            if let error = value.quality.meanAbsoluteErrorMinutes {
                                Text("\(value.quality.evaluatedCount) riscontri · scarto medio \(Int(ceil(error))) min").font(.caption)
                            } else { Text("Riscontri previsto/reale dalle prossime sedute.").font(.caption).foregroundStyle(PivotTheme.muted) }
                        } else { Text("Non ci sono ancora 3 sedute complete confrontabili.").font(.subheadline).foregroundStyle(PivotTheme.muted) }
                        if let library = store.data.training, let plan = library.plans.first(where: { $0.id == value.planID }),
                           let day = plan.payload.days.first(where: { $0.id == value.dayID }) {
                            NavigationLink("Apri la seduta") { TrainingSessionView(plan: plan, day: day, library: library, event: nil) }
                                .frame(minHeight: 44)
                        }
                    }
                }
            }
            if let goals = store.data.savingsBudget?.goals.filter({ !$0.archived }), !goals.isEmpty {
                SectionHeading(title: "Scenari Salvadanaio")
                ForEach(goals) { goal in
                    NavigationLink { SavingsForecastView(goalID: goal.id) } label: {
                        PivotCard(tint: PivotTheme.amber) { ActionRow(title: goal.name, subtitle: "Simula una quota settimanale, senza movimenti", icon: "eurosign.circle") }
                    }.buttonStyle(.plain)
                }
            }
            if let refreshedAt { Text("Aggiornato alle \(PivotDate.time(refreshedAt)) · solo dati disponibili sul dispositivo").font(.caption).foregroundStyle(PivotTheme.muted) }
            Button("Aggiorna previsioni") { refreshID = UUID() }.buttonStyle(PivotSecondaryButton())
        }.navigationTitle("Previsioni")
            .task(id: refreshKey) { await refresh() }
    }
    private var dayCard: some View {
        PivotCard {
            Label("La giornata, adesso", systemImage: "sun.max").font(.headline)
            if !calendar.hasAccess {
                Text("Consenti il Calendario per valutare impegni e spazi disponibili.").font(.subheadline).foregroundStyle(PivotTheme.muted)
            } else if let day {
                if let sleep = day.sleepMinutes {
                    Text("Sonno registrato \(sleep / 60) h \(sleep % 60) min · \(day.sleepSource == .health ? "Salute" : "diario")")
                } else { Text("Sonno non disponibile").foregroundStyle(PivotTheme.muted) }
                if let energy = day.reportedEnergy { Text("Energia indicata da te: \(energy)/10") }
                else { Text("Energia non indicata").foregroundStyle(PivotTheme.muted) }
                if let fatigue = day.reportedFatigue { Text("Stanchezza indicata da te: \(fatigue)/10") }
                Text("\(day.scheduledMinutes) min occupati · \(day.freeMinutes) min non occupati fino all’inizio delle ore tranquille")
                    .font(.subheadline).accessibilityIdentifier("prediction-day-load")
                if day.unknownTravelCount > 0 {
                    Text("\(day.unknownTravelCount) tragitti da verificare: gli spazi non occupati non sono ancora tutti utilizzabili.").foregroundStyle(PivotTheme.amber)
                }
                if day.allDayBusy { Text("C’è un impegno per l’intera giornata: non lo considero tempo libero.").foregroundStyle(PivotTheme.amber) }
                if day.missedUnconfirmedCount > 0 { Text("\(day.missedUnconfirmedCount) attività passate senza esito. Conferma cosa hai fatto prima di recuperarle.") }
                if (day.reportedEnergy.map { $0 <= 3 } ?? false) || (day.reportedFatigue.map { $0 >= 7 } ?? false) {
                    Text("Hai indicato poca energia o molta stanchezza. Puoi valutare una giornata più leggera; Pivot non annulla attività né decide un recupero medico.").foregroundStyle(PivotTheme.amber)
                }
                Text("Nessun punteggio biologico o diagnosi: sonno e valutazioni personali descrivono il contesto, non provano cosa hai fatto.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
            } else { Text("Contesto non disponibile: controlla le ore tranquille nelle impostazioni.").foregroundStyle(PivotTheme.muted) }
        }.font(.subheadline)
    }
    private func refresh() async {
        let snapshot = store.data, events = calendar.events, now = Date()
        let output = await Task.detached(priority: .userInitiated) {
            let context = DayPlanningContext.make(events: events, data: snapshot, now: now)
            let library = snapshot.training ?? TrainingLibrary()
            let values: [TrainingForecastSummary] = library.activePlan.map { plan in
                plan.payload.days.map { day in
                    .init(planID: plan.id, dayID: day.id, name: day.name,
                          estimate: TrainingDurationEstimate.make(plan: plan, day: day, library: library, calendarMinutes: nil, now: now),
                          quality: TrainingPredictionQuality.make(TrainingHistory.sessions(planID: plan.id, dayID: day.id, dayName: day.name, library: library)))
                }
            } ?? []
            return (context, values)
        }.value
        guard !Task.isCancelled, snapshot.updatedAt == store.data.updatedAt else { return }
        day = output.0; durations = output.1; refreshedAt = now
    }
}
