import SwiftUI

struct WorkoutRestAudioSettingsView: View {
    @EnvironmentObject private var store: PivotStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var audio = WorkoutRestAlarmService.shared
    @State private var volumeStep = 5.0
    @State private var savingVolume = false
    private var settings: WorkoutRestAudioSettings { store.data.settings.workoutRestAudio ?? .init() }
    var body: some View {
        PivotScreen {
            PivotHeader(title: "Avviso recupero", subtitle: "Allarme di sistema · stop manuale")
            PivotCard {
                Text("Allarme dall’iPhone").font(.headline)
                Text("Alla fine del recupero parte l’allarme: premi Ferma sull’iPhone per interromperlo. Pausa, reset, passaggio alla serie successiva e fine allenamento aggiornano o annullano l’allarme.")
                    .font(.subheadline)
                Text("L’interruzione della musica è gestita da iOS insieme all’allarme, non da un secondo timer. Non cambio il volume generale del telefono e non riproduco un bip separato nelle cuffie. Uscita audio e comportamento del lettore musicale vanno verificati sul dispositivo.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
                if settings.enabled {
                    Label(audio.authorized ? "Attivo" : "Da autorizzare in iOS", systemImage: audio.authorized ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .foregroundStyle(audio.authorized ? PivotTheme.accent : PivotTheme.amber)
                        .accessibilityIdentifier("rest-audio-enabled")
                    if !audio.authorized {
                        Button("Autorizza gli allarmi") { Task { await audio.enable(store: store) } }
                            .buttonStyle(PivotPrimaryButton())
                    }
                    Button("Disattiva allarme recupero") { Task { await audio.disable(store: store) } }
                        .buttonStyle(PivotSecondaryButton()).accessibilityIdentifier("rest-audio-disable")
                } else {
                    Button("Attiva allarme recupero") { Task { await audio.enable(store: store) } }
                        .buttonStyle(PivotPrimaryButton()).accessibilityIdentifier("rest-audio-enable")
                    Text("Senza questa autorizzazione il timer resta visibile, ma non aggiungo suoni alternativi nelle cuffie.")
                        .font(.caption).foregroundStyle(PivotTheme.muted)
                }
            }.disabled(store.locked || audio.busy || savingVolume)
            PivotCard {
                LabeledContent("Volume dei prossimi avvisi", value: "\(Int(volumeStep) * 5)%")
                Slider(value: $volumeStep, in: 1...20, step: 1, onEditingChanged: { editing in if !editing { saveVolume() } })
                    .accessibilityLabel("Volume avviso recupero").accessibilityIdentifier("rest-audio-volume")
                    .disabled(store.locked || audio.busy || savingVolume)
                Text("Regola il suono di Pivot, non la musica. Il livello effettivo dipende anche dal volume di uscita impostato in iOS. Un allarme già in corso non viene riavviato per applicare il nuovo valore.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
            }
            PivotCard {
                Text(audio.message).font(.subheadline).accessibilityIdentifier("rest-audio-status")
                ForEach((store.data.training?.sessions ?? []).filter { $0.end == nil && $0.rest?.deadline != nil }) { session in
                    Text(session.dayName).font(.headline)
                    Button("Ferma allarme di questo recupero") { Task { await audio.stop(sessionID: session.id) } }
                        .buttonStyle(PivotSecondaryButton()).accessibilityIdentifier("rest-audio-stop")
                    if let deadline = session.rest?.deadline, deadline > Date() {
                        Button("Riattiva per questo recupero") { Task { await WorkoutRuntime.scheduleRest(session, forceAlarm: true) } }
                            .disabled(!settings.enabled).accessibilityIdentifier("rest-audio-rearm")
                    }
                }
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("--rest-alarm-test") {
                    Text("Allarmi sintetici: \(audio.syntheticAlarmCount)").accessibilityIdentifier("rest-audio-test-count")
                }
                #endif
            }.disabled(store.locked || audio.busy)
            if #available(iOS 26.0, *) {
                NavigationLink { WorkoutAlarmProbeView() } label: { Label("Prova con cuffie e schermo spento", systemImage: "testtube.2") }
            }
        }.navigationTitle("Audio recupero")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }
            .onAppear { volumeStep = Double(settings.volumeStep) }
    }
    private func saveVolume() {
        guard !store.locked, !savingVolume else { return }
        var updated = settings; updated.volumeStep = Int(volumeStep)
        guard updated.isValid, store.change({ $0.settings.workoutRestAudio = updated }) else { return }
        savingVolume = true
        Task {
            defer { savingVolume = false }
            guard await store.flushPendingWrites() else { return }
            for session in store.data.training?.sessions ?? [] where session.end == nil {
                await WorkoutRuntime.scheduleRest(session)
            }
        }
    }
}
