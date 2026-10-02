import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: PivotStore
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var notifications: NotificationService
    @State private var settings = Settings()
    @State private var folderPicker = false
    @State private var importing = false
    @State private var pendingRestore: URL?
    @State private var restoreApproval = false
    @State private var exporting = false
    @State private var exportFile: URL?
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Protezione dello storico") {
                    Text(store.backupStatus).foregroundStyle(store.lastExternalBackup == nil ? .orange : .secondary)
                    if let last = store.lastExternalBackup { Text("Ultima copia esterna: \(last.formatted(date: .abbreviated, time: .shortened))").font(.caption) }
                    Button("Scegli cartella backup in File / iCloud Drive") { folderPicker = true }.disabled(store.locked)
                    Button("Aggiorna backup esterno") { store.backupNow() }.disabled(store.locked)
                    Button("Esporta backup completo") {
                        do { exportFile = try store.exportURL(); exporting = true }
                        catch { message = error.localizedDescription }
                    }
                    Button("Ripristina un backup") { importing = true }
                    Text("Scegli una cartella fuori da ‘Sul mio iPhone → Pivot’, preferibilmente iCloud Drive. La copia locale non sopravvive alla cancellazione dell'app. Dopo una reinstallazione seleziona il backup e riconfigura la cartella. I backup contengono dati personali: non pubblicarli su GitHub.").font(.caption)
                }
                Section("Calendari") {
                    Toggle("Escludi festività", isOn: $settings.excludeHolidays)
                    ForEach(calendar.choices) { choice in
                        Toggle(isOn: Binding(get: { !settings.excludedCalendarIDs.contains(choice.id) && !settings.excludedCalendarTitles.contains(choice.title) }, set: { enabled in
                            settings.excludedCalendarIDs.removeAll { $0 == choice.id }
                            settings.excludedCalendarTitles.removeAll { $0 == choice.title }
                            if !enabled { settings.excludedCalendarIDs.append(choice.id); settings.excludedCalendarTitles.append(choice.title) }
                        })) { Label(choice.title, systemImage: "circle.fill").foregroundStyle(Color(pivotHex: choice.colorHex)) }
                    }
                    Button("Consenti / aggiorna calendari") { Task { await calendar.requestAccess(); calendar.refresh(settings: settings) } }
                }
                Section("Notifiche") {
                    Button("Consenti notifiche") { Task { await notifications.requestAccess(); await notifications.schedule(events: calendar.events, data: store.data) } }
                    Text(notifications.status).font(.caption)
                    Stepper("Controllo mattina: +\(settings.morningDelayMinutes) min", value: $settings.morningDelayMinutes, in: 10...120, step: 5)
                    Toggle("Dopo il secondo avviso, ricorda ogni ora", isOn: $settings.repeatMissedNotifications)
                    Stepper("Fine avvisi: \(settings.quietStartHour):00", value: $settings.quietStartHour, in: 19...23)
                    Stepper("Ripresa avvisi: \(settings.quietEndHour):00", value: $settings.quietEndHour, in: 5...10)
                    Stepper("Resoconto serale: \(settings.eveningHour):\(String(format: "%02d", settings.eveningMinute))", value: $settings.eveningHour, in: 19...22)
                    Text("Pranzo, merenda e cena: avvisi a −30 e −10 minuti. Se li ricevi anche dal Calendario, potresti avere doppie notifiche. Gli avvisi sono locali: Pivot non resta sempre attivo in sottofondo. Aprilo ogni giorno e dopo modifiche al calendario.").font(.caption)
                }
                Section("Esami e priorità") {
                    Toggle("Studio non più recuperabile: mettilo in priorità", isOn: $settings.studyMustTakePriority)
                    DatePicker("A partire da", selection: Binding(get: { settings.studyPriorityFrom ?? Date() }, set: { settings.studyPriorityFrom = $0 }), displayedComponents: .date)
                    Text("Questa scelta non sposta da sola gli impegni fissi. La prima versione propone recuperi completi; le compressioni di altri eventi saranno concordate manualmente.").font(.caption)
                }
                Button("Salva impostazioni") {
                    if store.change({ $0.settings = settings }) {
                        calendar.refresh(settings: settings)
                        message = "Impostazioni salvate."
                    }
                }.disabled(store.locked)
                Section("Pivot 0.1") {
                    Text("App nativa personale. Nessuna API IA a pagamento, nessun invio automatico a ChatGPT. Tema scuro e colori del calendario. Tariffe e pagamenti si inseriscono manualmente.").font(.caption)
                    Text("Aggiorna installando sopra l'app esistente, con lo stesso Apple ID e identificativo. Prima di ogni aggiornamento verifica un backup esterno. Non cancellare Pivot per rinnovarlo.").font(.caption)
                }
                if let message { Text(message).foregroundStyle(.orange) }
            }.navigationTitle("Impostazioni")
                .onAppear { settings = store.data.settings }
                .sheet(isPresented: $folderPicker) { FolderPicker { store.selectBackupFolder($0) } }
                .sheet(isPresented: $exporting) { if let exportFile { ShareSheet(items: [exportFile]) } }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    switch result {
                    case .success(let url): pendingRestore = url; restoreApproval = true
                    case .failure(let error): message = error.localizedDescription
                    }
                }
                .alert("Ripristinare lo storico?", isPresented: $restoreApproval) {
                    Button("Annulla", role: .cancel) { pendingRestore = nil }
                    Button("Confermo il ripristino") {
                        if let url = pendingRestore { store.restore(url); settings = store.data.settings }
                        pendingRestore = nil
                    }
                } message: { Text("Il backup sostituirà i dati attuali. Pivot conserva una copia locale dei dati precedenti; un file non valido non verrà applicato.") }
        }
    }
}
