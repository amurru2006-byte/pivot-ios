import SwiftUI

@available(iOS 26.0, *)
struct WorkoutAlarmProbeView: View {
    @EnvironmentObject private var store: PivotStore
    @Environment(\.scenePhase) private var scene
    @StateObject private var probe = WorkoutAlarmProbe()
    @State private var confirmed = false
    var body: some View {
        PivotScreen {
            PivotCard(tint: PivotTheme.amber) {
                Label("Prova tecnica, non recupero", systemImage: "testtube.2").font(.headline)
                Text("Serve a verificare dove suona un allarme di sistema con cuffie Bluetooth collegate e schermo bloccato. Non attiva questa modalità per gli allenamenti.")
                Text("Il file contiene tre bip in due secondi; iOS può ripeterlo finché non premi Ferma. Questo è un allarme con stop manuale: verifica che la musica nelle cuffie venga interrotta o attenuata insieme al bip e cosa succede quando lo fermi.")
                    .font(.subheadline).foregroundStyle(PivotTheme.amber)
                Text("Il test può suonare anche in modalità silenziosa o Full immersion. Il volume dipende anche da iOS: prima abbassalo a un livello confortevole e fai la prova in un posto adatto.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
            }
            PivotCard {
                Text("1. Collega le cuffie Bluetooth e avvia la musica, se la usi.")
                Text("2. Avvia il test e consenti gli allarmi soltanto se iOS te lo chiede.")
                Text("3. Blocca lo schermo: l’allarme è previsto dopo 20 secondi.")
                Text("4. Nota se suona dal telefono, dalle cuffie o da entrambi, se ripete i bip e cosa succede alla musica. Poi premi Ferma, se necessario.")
                Toggle("Ho letto: potrei dover fermare l’allarme", isOn: $confirmed)
                    .accessibilityIdentifier("alarm-probe-confirm")
                Button("Avvia prova tra 20 secondi") { Task { await probe.start() } }
                    .buttonStyle(PivotPrimaryButton())
                    .disabled(!confirmed || probe.busy || probe.scheduled || store.locked)
                    .accessibilityIdentifier("alarm-probe-start")
                Button("Ferma test") { probe.cancel() }
                    .buttonStyle(PivotSecondaryButton()).disabled(probe.busy)
                    .accessibilityIdentifier("alarm-probe-stop")
                Text(probe.message).font(.subheadline).accessibilityIdentifier("alarm-probe-status")
                Text("Nessun microfono, audio registrato, dato Salute o invio all’AI. Questa prova non modifica calendario, allenamenti o altre sveglie.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
            }
        }.navigationTitle("Test avviso a schermo spento")
            .onAppear { probe.refresh() }
            .onChange(of: scene) { _, value in if value == .active { probe.refresh() } }
    }
}
