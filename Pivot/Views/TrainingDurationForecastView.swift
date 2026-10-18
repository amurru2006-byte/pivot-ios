import SwiftUI

struct TrainingDurationForecastView: View {
    @EnvironmentObject private var store: PivotStore
    let session: TrainingSession
    let event: CalendarItem?
    @State private var estimate: TrainingDurationEstimate?
    @State private var quality = TrainingPredictionQuality.make([])
    @State private var workloadRevision = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let estimate {
                Label("Durata prevista · \(estimate.activityMinutes) min", systemImage: "clock")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(PivotTheme.accent)
                    .accessibilityIdentifier("training-duration-prediction")
                if let stats = estimate.statistics {
                    Text("Fascia osservata \(stats.lowerMinutes)–\(stats.upperMinutes) min · \(stats.count) sedute confrontabili")
                        .font(.caption).foregroundStyle(PivotTheme.muted).accessibilityIdentifier("training-duration-band")
                } else {
                    Text("Durata del calendario: lo storico è ancora insufficiente.").font(.caption).foregroundStyle(PivotTheme.muted)
                }
                DisclosureGroup("Dettagli della stima") {
                    if estimate.provisional { Text("Stima provvisoria: pochi allenamenti confrontabili.").font(.caption) }
                    if let band = estimate.timeBand { Text("Confronto con le sedute della \(band.label).").font(.caption) }
                    if let stats = estimate.statistics {
                        Text("La fascia descrive la parte centrale delle durate osservate, non una garanzia. Non comprende preparazione e tragitti.").font(.caption)
                        Text("Minimo \(stats.minimumMinutes) min · massimo \(stats.maximumMinutes) min").font(.caption)
                    }
                    if let error = quality.meanAbsoluteErrorMinutes {
                        Text("\(quality.evaluatedCount) riscontri · errore medio \(Int(ceil(error))) min")
                            .font(.caption).accessibilityIdentifier("training-duration-quality")
                    } else { Text("Il confronto previsto/reale inizierà con le prossime sedute.").font(.caption) }
                }.font(.caption).foregroundStyle(PivotTheme.muted)
            } else {
                Label("Durata da conoscere", systemImage: "clock.badge.questionmark").font(.subheadline)
                Text("Servono almeno 3 sedute complete confrontabili, oppure la durata del tuo evento a calendario.")
                    .font(.caption).foregroundStyle(PivotTheme.muted).accessibilityIdentifier("training-duration-insufficient")
            }
        }.task(id: refreshKey) { await refresh() }
            .onChange(of: session.exercises.map(\.exercise)) { _, _ in workloadRevision = UUID() }
    }
    private var refreshKey: String {
        "\(store.data.updatedAt.timeIntervalSinceReferenceDate)|\(workloadRevision)|\(session.id)|\(session.phase?.rawValue ?? "unknown")|\(event?.start.timeIntervalSinceReferenceDate ?? 0)|\(event?.durationMinutes ?? 0)"
    }
    private func refresh() async {
        let library = store.data.training ?? TrainingLibrary(), now = Date()
        let snapshot = session, calendarMinutes = event?.durationMinutes
        let result = await Task.detached(priority: .userInitiated) {
            let estimate = TrainingDurationEstimate.make(session: snapshot, library: library, calendarMinutes: calendarMinutes,
                                                        now: now, scheduledStart: event.flatMap { $0.start >= now ? $0.start : nil })
            let samples = TrainingHistory.sessions(planID: snapshot.planID, dayID: snapshot.dayID, dayName: snapshot.dayName, library: library)
            return (estimate, TrainingPredictionQuality.make(samples))
        }.value
        guard !Task.isCancelled else { return }
        estimate = result.0; quality = result.1
    }
}

struct SavedTrainingDurationView: View {
    let session: TrainingSession
    var body: some View {
        if let prediction = session.durationPrediction {
            DisclosureGroup("Previsione all’avvio · \(prediction.expectedMinutes) min") {
                if let actual = prediction.actualMinutes(for: session) {
                    Text("Durata reale \(Int(ceil(actual))) min · scarto \(Int(ceil(abs(actual - Double(prediction.expectedMinutes))))) min")
                        .accessibilityIdentifier("training-duration-feedback")
                } else if session.end != nil {
                    Text("Confronto non disponibile: verifica esclusione, orari e programmazione della seduta.")
                }
                if let lower = prediction.lowerMinutes, let upper = prediction.upperMinutes {
                    Text("Fascia osservata all’avvio: \(lower)–\(upper) min")
                }
                Text("La previsione originale resta conservata: non viene ricalcolata dopo l’allenamento.")
            }.font(.caption).foregroundStyle(PivotTheme.muted).accessibilityIdentifier("training-duration-saved")
        }
    }
}
