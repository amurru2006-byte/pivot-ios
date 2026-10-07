import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
    @EnvironmentObject var store: PivotStore
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var notifications: NotificationService
    @EnvironmentObject var health: HealthService
    @EnvironmentObject var agenda: AgendaService
    @State private var settings = Settings()
    @State private var folderPicker = false
    @State private var importing = false
    @State private var pendingRestore: URL?
    @State private var restoreApproval = false
    @State private var exporting = false
    @State private var exportFile: URL?
    @State private var message: String?
    @State private var saveTask: Task<Void, Never>?
    private var installedVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    var body: some View {
        NavigationStack {
            PivotScreen {
                PivotHeader(title: "Su misura per te", subtitle: "Calendari, promemoria e i tuoi dati al sicuro.")
                VStack(spacing: 12) {
                    settingsLink("Calendari", subtitle: "Colori e sincronizzazione", icon: "calendar") { calendarSettings }
                    settingsLink("Salute e Apple Watch", subtitle: "Sonno e allenamenti", icon: "heart.text.square.fill") { healthSettings }
                    settingsLink("Notifiche", subtitle: "Quando e come avvisarti", icon: "bell.fill") { notificationSettings }
                    settingsLink("Backup e privacy", subtitle: "Proteggi il tuo storico", icon: "externaldrive.fill") { backupSettings }
                    settingsLink("Studio ed esami", subtitle: "Priorità e recuperi", icon: "graduationcap.fill") { studySettings }
                    settingsLink("Energia e riferimenti", subtitle: "Obiettivi dei valori da 0 a 10", icon: "chart.dots.scatter") { ratingSettings }
                    settingsLink("Prestazioni e salvataggio", subtitle: "Tempi di caricamento e stato dei dati", icon: "speedometer") { PerformanceView() }
                }
                Text("Le impostazioni si salvano automaticamente.").font(.caption).foregroundStyle(PivotTheme.muted)





                Button { Task { await saveSettings() } } label: { Label("Salva impostazioni", systemImage: "checkmark.circle.fill") }.buttonStyle(PivotPrimaryButton()).disabled(store.locked)
                if let message { Label(message, systemImage: "info.circle").font(.subheadline).foregroundStyle(PivotTheme.amber) }
                HStack {
                    Text("PIVOT").font(.system(.caption, design: .rounded, weight: .bold)).tracking(3)
                    Spacer(); Text("\(installedVersion) · Il tuo punto di svolta").font(.caption)
                }.foregroundStyle(PivotTheme.muted).padding(.top, 4)
            }.navigationTitle("Impostazioni")
                .onAppear { settings = store.data.settings }
                .onChange(of: store.isLoading) { _, loading in if !loading { settings = store.data.settings } }
                .onChange(of: settings) { _, _ in
                    saveTask?.cancel()
                    guard !store.isLoading, settings != store.data.settings else { return }
                    saveTask = Task {
                        do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
                        guard !Task.isCancelled, settings != store.data.settings else { return }
                        store.change { $0.settings = settings }
                    }
                }
                .onDisappear {
                    saveTask?.cancel()
                    if !store.isLoading, settings != store.data.settings { store.change { $0.settings = settings } }
                }
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
                        if let url = pendingRestore { Task { await store.restore(url); settings = store.data.settings } }
                        pendingRestore = nil
                    }
                } message: { Text("Il backup sostituirà i dati attuali. Pivot conserva una copia locale dei dati precedenti; un file non valido non verrà applicato.") }
        }
    }
    private var ratingSettings: some View {
        PivotCard {
            ForEach(RatingMetric.allCases) { metric in
                Picker(metric.label, selection: Binding(get: { metric.target(in: settings) ?? -1 }, set: { value in
                    var targets = settings.ratingTargets ?? [:]; targets[metric.rawValue] = value; settings.ratingTargets = targets
                })) {
                    Text("Nessun obiettivo").tag(-1)
                    ForEach(0...10, id: \.self) { Text("\($0)/10").tag($0) }
                }
            }
            Text("Obiettivo dorato, media storica blu. La media usa le 4 settimane complete precedenti alla settimana dell'evento: prima la media di ogni settimana, poi la media delle settimane con dati. I valori non indicati non sono zeri. Questi riferimenti non compilano le tue sensazioni.").font(.caption).foregroundStyle(PivotTheme.muted)
        }
    }
    private var healthSettings: some View {
    PivotCard(tint: PivotTheme.accent) {
        Label("Salute e Apple Watch", systemImage: "heart.text.square.fill").font(.headline)
        Text(health.status).font(.subheadline).foregroundStyle(PivotTheme.muted)
        Button("Collega app Salute") { Task { await health.connect(store: store, events: calendar.events); settings = store.data.settings } }
            .buttonStyle(PivotPrimaryButton()).disabled(health.isRefreshing || store.locked)
        Button("Aggiorna dati da Salute") { Task { await health.refresh(store: store, events: calendar.events, force: true) } }
            .buttonStyle(PivotSecondaryButton()).disabled(health.isRefreshing || store.data.settings.healthEnabled != true)
        Text("Sola lettura, quando apri Pivot. Nessuna registrazione continua. Le camminate fuori dagli orari di allenamento restano attività generale. Per revocare i permessi usa l’app Salute.").font(.caption).foregroundStyle(PivotTheme.muted)
                Toggle("Leggi Salute all’apertura", isOn: Binding(get: { settings.healthEnabled == true }, set: { settings.healthEnabled = $0 }))
                DisclosureGroup("Quando chiedere se una camminata vale come cardio") {
                    Stepper("Durata minima: \(settings.cardioReviewMinimumMinutes ?? 20) min", value: Binding(get: { settings.cardioReviewMinimumMinutes ?? 20 }, set: { settings.cardioReviewMinimumMinutes = $0 }), in: 5...120, step: 5)
                    Stepper("Calorie attive minime: \(settings.cardioReviewMinimumCalories ?? 100)", value: Binding(get: { settings.cardioReviewMinimumCalories ?? 100 }, set: { settings.cardioReviewMinimumCalories = $0 }), in: 0...1000, step: 25)
                    Text("Sono filtri modificabili per evitare domande sui tragitti brevi, non una misura medica dello sforzo. Fuori orario serve sempre la tua conferma; senza calorie disponibili non considero la camminata cardio in automatico.").font(.caption).foregroundStyle(PivotTheme.muted)
                }
        Toggle("Includi i dati Salute nei backup e resoconti", isOn: Binding(get: { settings.includeHealthInExports == true }, set: { settings.includeHealthInExports = $0 }))
        Text("Senza questa scelta i dati importati restano locali. I backup esterni non sono cifrati da Pivot: non condividerli pubblicamente.").font(.caption).foregroundStyle(PivotTheme.muted)
        Toggle("Includi la chat con Pivot nei resoconti", isOn: Binding(get: { settings.includeCoachInReports != false }, set: { settings.includeCoachInReports = $0 }))
    }
    }
    private var backupSettings: some View {
    PivotCard(tint: PivotTheme.blue) {
        ActionRow(title: "I tuoi dati", subtitle: store.lastExternalBackup == nil ? "Configura il backup in iCloud Drive." : "Copia esterna configurata", icon: "externaldrive.badge.icloud")
        Text(store.backupStatus).font(.caption).foregroundStyle(store.lastExternalBackup == nil ? PivotTheme.amber : PivotTheme.muted)
        if let last = store.lastExternalBackup { Text("Ultima copia: \(DisplayDate.label(last, format: "d MMM · HH:mm"))").font(.caption).foregroundStyle(PivotTheme.muted) }
        Button("Scegli cartella backup") { folderPicker = true }.buttonStyle(PivotSecondaryButton()).disabled(store.locked)
        DisclosureGroup("Gestisci backup e ripristino") {
            VStack(alignment: .leading, spacing: 16) {
                Button("Aggiorna copia esterna") { store.backupNow() }.disabled(store.locked)
                Button("Esporta backup completo") {
                    Task {
                        do { exportFile = try await store.exportURL(); exporting = true }
                        catch { message = error.localizedDescription }
                    }
                }
                Button("Ripristina un backup…") { importing = true }
                Text("Scegli una cartella in iCloud Drive, fuori da Pivot. Prima di aggiornare verifica il backup; installa la nuova versione sopra quella attuale. Se cancelli l'app, la copia locale viene eliminata. I backup contengono dati personali.").font(.caption).foregroundStyle(PivotTheme.muted)
            }.padding(.top, 12)
        }.font(.subheadline)
    }
    }
    private var calendarSettings: some View {
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
    }
    private var notificationSettings: some View {
    PivotCard {
        Label("Promemoria", systemImage: "bell.badge.fill").font(.headline).foregroundStyle(PivotTheme.amber)
        Text(notifications.status).font(.subheadline).foregroundStyle(PivotTheme.muted)
        Button("Consenti notifiche") { Task { await notifications.requestAccess(); await notifications.schedule(events: agenda.planned, data: store.data) } }.buttonStyle(PivotSecondaryButton())
        Button("Apri impostazioni notifiche di iOS") {
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
        }.font(.subheadline).foregroundStyle(PivotTheme.accent)
        DisclosureGroup("Orari e frequenza") {
            VStack(alignment: .leading, spacing: 16) {
                Stepper("Mattina: dopo \(settings.morningDelayMinutes) min", value: $settings.morningDelayMinutes, in: 10...120, step: 5)
                Toggle("Un secondo avviso dopo 30 minuti", isOn: $settings.repeatMissedNotifications)
                Stepper("Fine avvisi: \(settings.quietStartHour):00", value: $settings.quietStartHour, in: 19...23)
                Stepper("Ripresa avvisi: \(settings.quietEndHour):00", value: $settings.quietEndHour, in: 5...10)
                Stepper("Resoconto: \(settings.eveningHour):\(String(format: "%02d", settings.eveningMinute))", value: $settings.eveningHour, in: 19...22)
                Text("Pasti: 30 e 10 minuti prima. Altri impegni: 10 minuti prima e una domanda alla fine. Nessun avviso ogni ora. Gli avvisi del Calendario potrebbero duplicarli. Su Apple Watch arrivano secondo le impostazioni notifiche dell’iPhone e di Watch.").font(.caption).foregroundStyle(PivotTheme.muted)
            }.padding(.top, 12)
        }.font(.subheadline)
    }
    }
    private var studySettings: some View {
    PivotCard {
        Label("Studio ed esami", systemImage: "graduationcap.fill").font(.headline).foregroundStyle(PivotTheme.blue)
        Toggle("Dai priorità allo studio non recuperabile", isOn: $settings.studyMustTakePriority)
        if settings.studyMustTakePriority {
            DatePicker("A partire da", selection: Binding(get: { settings.studyPriorityFrom ?? Date() }, set: { settings.studyPriorityFrom = $0 }), displayedComponents: .date)
            Text("Gli impegni fissi restano protetti. Accorciamenti e rinunce si concordano prima di applicarli.").font(.caption).foregroundStyle(PivotTheme.muted)
        }
    }
    }
    private func settingsLink<Content: View>(_ title: String, subtitle: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        NavigationLink { PivotScreen { content() }.navigationTitle(title) } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).foregroundStyle(PivotTheme.accent).frame(width: 46, height: 46).background(PivotTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(PivotTheme.text)
                    Text(subtitle).font(.caption).foregroundStyle(PivotTheme.muted)
                }
                Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(PivotTheme.muted)
            }.padding(15).background(PivotTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain)
    }
    private func saveSettings() async {
        saveTask?.cancel()
        guard store.change({ $0.settings = settings }) else { return }
        if await store.flushPendingWrites() { message = "Impostazioni salvate." }
    }
}
