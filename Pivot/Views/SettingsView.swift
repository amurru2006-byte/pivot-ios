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
            PivotScreen {
                PivotHeader(title: "Su misura per te", subtitle: "Calendari, promemoria e i tuoi dati al sicuro.")
                PivotCard(tint: PivotTheme.blue) {
                    ActionRow(title: "I tuoi dati", subtitle: store.lastExternalBackup == nil ? "Configura il backup in iCloud Drive." : "Copia esterna configurata", icon: "externaldrive.badge.icloud")
                    Text(store.backupStatus).font(.caption).foregroundStyle(store.lastExternalBackup == nil ? PivotTheme.amber : PivotTheme.muted)
                    if let last = store.lastExternalBackup { Text("Ultima copia: \(DisplayDate.label(last, format: "d MMM · HH:mm"))").font(.caption).foregroundStyle(PivotTheme.muted) }
                    Button("Scegli cartella backup") { folderPicker = true }.buttonStyle(PivotSecondaryButton()).disabled(store.locked)
                    DisclosureGroup("Gestisci backup e ripristino") {
                        VStack(alignment: .leading, spacing: 16) {
                            Button("Aggiorna copia esterna") { store.backupNow() }.disabled(store.locked)
                            Button("Esporta backup completo") {
                                do { exportFile = try store.exportURL(); exporting = true }
                                catch { message = error.localizedDescription }
                            }
                            Button("Ripristina un backup…") { importing = true }
                            Text("Scegli una cartella in iCloud Drive, fuori da Pivot. Prima di aggiornare verifica il backup; installa la nuova versione sopra quella attuale. Se cancelli l'app, la copia locale viene eliminata. I backup contengono dati personali.").font(.caption).foregroundStyle(PivotTheme.muted)
                        }.padding(.top, 12)
                    }.font(.subheadline)
                }
                PivotCard {
                    Label("Calendari", systemImage: "calendar").font(.headline).foregroundStyle(PivotTheme.blue)
                    Toggle("Escludi festività", isOn: $settings.excludeHolidays)
                    DisclosureGroup("Scegli quali seguire") {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(calendar.choices) { choice in
                                if settings.excludeHolidays && choice.holiday {
                                    HStack { Label(choice.title, systemImage: "circle.fill").foregroundStyle(Color(pivotHex: choice.colorHex)); Spacer(); Text("Escluso").font(.caption).foregroundStyle(PivotTheme.muted) }
                                } else {
                                    Toggle(isOn: Binding(get: { !settings.excludedCalendarIDs.contains(choice.id) && !settings.excludedCalendarTitles.contains(choice.title) }, set: { enabled in
                                        settings.excludedCalendarIDs.removeAll { $0 == choice.id }
                                        settings.excludedCalendarTitles.removeAll { $0 == choice.title }
                                        if !enabled { settings.excludedCalendarIDs.append(choice.id); settings.excludedCalendarTitles.append(choice.title) }
                                    })) { Label(choice.title, systemImage: "circle.fill").foregroundStyle(Color(pivotHex: choice.colorHex)) }
                                }
                            }
                            Button("Consenti / aggiorna calendari") { Task { await calendar.requestAccess(); await calendar.refresh(settings: settings) } }.buttonStyle(PivotSecondaryButton())
                        }.padding(.top, 12)
                    }.font(.subheadline)
                }
                PivotCard {
                    Label("Promemoria", systemImage: "bell.badge.fill").font(.headline).foregroundStyle(PivotTheme.amber)
                    Text(notifications.status).font(.subheadline).foregroundStyle(PivotTheme.muted)
                    Button("Consenti notifiche") { Task { await notifications.requestAccess(); await notifications.schedule(events: calendar.events, data: store.data) } }.buttonStyle(PivotSecondaryButton())
                    DisclosureGroup("Orari e frequenza") {
                        VStack(alignment: .leading, spacing: 16) {
                            Stepper("Mattina: dopo \(settings.morningDelayMinutes) min", value: $settings.morningDelayMinutes, in: 10...120, step: 5)
                            Toggle("Ripeti ogni ora gli avvisi saltati", isOn: $settings.repeatMissedNotifications)
                            Stepper("Fine avvisi: \(settings.quietStartHour):00", value: $settings.quietStartHour, in: 19...23)
                            Stepper("Ripresa avvisi: \(settings.quietEndHour):00", value: $settings.quietEndHour, in: 5...10)
                            Stepper("Resoconto: \(settings.eveningHour):\(String(format: "%02d", settings.eveningMinute))", value: $settings.eveningHour, in: 19...22)
                            Text("Pranzo, merenda e cena: 30 e 10 minuti prima. Apri Pivot ogni giorno e dopo aver cambiato il calendario per aggiornare gli avvisi locali. Gli avvisi del Calendario potrebbero duplicarli.").font(.caption).foregroundStyle(PivotTheme.muted)
                        }.padding(.top, 12)
                    }.font(.subheadline)
                }
                PivotCard {
                    Label("Studio ed esami", systemImage: "graduationcap.fill").font(.headline).foregroundStyle(PivotTheme.blue)
                    Toggle("Dai priorità allo studio non recuperabile", isOn: $settings.studyMustTakePriority)
                    if settings.studyMustTakePriority {
                        DatePicker("A partire da", selection: Binding(get: { settings.studyPriorityFrom ?? Date() }, set: { settings.studyPriorityFrom = $0 }), displayedComponents: .date)
                        Text("Gli impegni fissi restano protetti. Accorciamenti e rinunce si concordano prima di applicarli.").font(.caption).foregroundStyle(PivotTheme.muted)
                    }
                }
                Button { Task { await saveSettings() } } label: { Label("Salva impostazioni", systemImage: "checkmark.circle.fill") }.buttonStyle(PivotPrimaryButton()).disabled(store.locked)
                if let message { Label(message, systemImage: "info.circle").font(.subheadline).foregroundStyle(PivotTheme.amber) }
                HStack {
                    Text("PIVOT").font(.system(.caption, design: .rounded, weight: .bold)).tracking(3)
                    Spacer(); Text("0.2 · Il tuo punto di svolta").font(.caption)
                }.foregroundStyle(PivotTheme.muted).padding(.top, 4)
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
    private func saveSettings() async {
        if store.change({ $0.settings = settings }) { await calendar.refresh(settings: settings); message = "Impostazioni salvate." }
    }
}
