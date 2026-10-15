import AlarmKit
import Combine
import SwiftUI

/// Explicit hardware experiment, never called by WorkoutRuntime. Scheduling a
/// one-off alarm does not assert speaker-only routing or automatic dismissal.
@available(iOS 26.0, *)
@MainActor
final class WorkoutAlarmProbe: ObservableObject {
    private struct Metadata: AlarmMetadata {}
    // Only this reserved probe is managed here, never all alarms in the app.
    private let id = UUID(uuidString: "DED90620-560D-459B-9075-C387D4960BC7")!
    @Published private(set) var scheduled = false
    @Published private(set) var busy = false
    @Published private(set) var message = "Nessun test avviato."

    func refresh() {
        guard !busy else { return }
        do { scheduled = try AlarmManager.shared.alarms.contains { $0.id == id } }
        catch { message = "Non riesco a verificare lo stato del test. Puoi comunque provare a fermarlo." }
    }

    func start() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let manager = AlarmManager.shared
            var authorization = manager.authorizationState
            if authorization == .notDetermined { authorization = try await manager.requestAuthorization() }
            guard authorization == .authorized else {
                message = "Allarmi non autorizzati. Non ho programmato il test. Puoi cambiare il permesso nelle impostazioni di iOS."
                return
            }
            // A second tap cannot leave a second pending alarm. Cancel only our
            // reserved probe, and don't replace it if cancellation fails.
            if try manager.alarms.contains(where: { $0.id == id }) { try manager.cancel(id: id) }
            scheduled = false
            let cue = await Task.detached(priority: .utility) { WorkoutRestChime.waveData(volume: 0.25) }.value
            guard let cue else { message = "Suono di prova non disponibile. Nessun allarme programmato."; return }
            let library = try FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let sounds = library.appendingPathComponent("Sounds", isDirectory: true)
            try FileManager.default.createDirectory(at: sounds, withIntermediateDirectories: true)
            try cue.write(to: sounds.appendingPathComponent("PivotRestProbe.wav"), options: .atomic)
            let alert = AlarmPresentation.Alert(title: "Pivot · prova audio", stopButton: AlarmButton(text: "Ferma test", textColor: .white, systemImageName: "stop.fill"))
            let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert), metadata: Metadata(), tintColor: Color.mint)
            let configuration = AlarmManager.AlarmConfiguration<Metadata>.alarm(
                schedule: .fixed(Date().addingTimeInterval(20)), attributes: attributes,
                sound: .named("PivotRestProbe.wav"))
            _ = try await manager.schedule(id: id, configuration: configuration)
            scheduled = true
            message = "Test programmato tra 20 secondi. Blocca ora lo schermo con le cuffie collegate. Se il suono si ripete, premi Ferma nell’allarme."
        } catch {
            // No raw errors, device identifiers, audio recording, or telemetry.
            message = "Non è stato possibile completare la programmazione. Usa Ferma test per annullare un eventuale test già presente."
        }
    }

    func cancel() {
        guard !busy else { return }
        do {
            let manager = AlarmManager.shared
            if try manager.alarms.contains(where: { $0.id == id }) { try manager.cancel(id: id) }
            scheduled = false
            message = "Test fermato. Nessuna modifica agli avvisi dei normali recuperi."
        } catch { message = "Non riesco a fermare il test dall’app. Se compare l’allarme, usa il suo pulsante Ferma." }
    }
}
