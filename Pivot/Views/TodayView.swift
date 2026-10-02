import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: PivotStore
    @EnvironmentObject var calendar: CalendarService
    @State private var finishedTutoring: CalendarItem?
    @State private var day = PreviewMode.enabled && PreviewMode.screen == "overnight" ? PivotDate.calendar.date(byAdding: .day, value: 1, to: Date())! : Date()
    var check: DayCheckIn? { store.data.checkIns[PivotDate.key(day)] }
    var body: some View {
        let effective = Planner.effectiveEvents(calendar.events, data: store.data)
        let dayEvents = effective.filter { $0.occurs(on: day) }
        let items = Planner.plannedEffectiveEvents(effective, data: store.data).filter { $0.occurs(on: day) }
        let attendance = Planner.universityAttendance(on: day, events: effective, data: store.data)
        let conflicts = Planner.overlapsInPlannedEvents(on: day, events: items)
        let completed = items.filter { store.data.records[$0.id]?.status == .completed }.count
        let minutes = items.reduce(0) { $0 + (store.data.records[$1.id]?.activeMinutes ?? 0) }
        NavigationStack {
            PivotScreen {
                PivotHeader(title: "La tua giornata", subtitle: DisplayDate.label(day).capitalized)
                if let sync = calendar.lastRefresh {
                    Label("Calendario aggiornato alle \(PivotDate.time(sync))", systemImage: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(PivotTheme.muted).accessibilityIdentifier("calendar-updated")
                }
                if calendar.isRefreshing {
                    Label("Aggiornamento calendario…", systemImage: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(PivotTheme.muted).accessibilityIdentifier("calendar-loading")
                }
                DaySelector(day: $day)
                HStack(alignment: .top, spacing: 9) {
                    MetricTile(title: "Completati", value: "\(completed)/\(items.count)", icon: "checkmark.circle.fill")
                    MetricTile(title: "Registrati", value: "\(minutes) min", icon: "clock.fill", color: PivotTheme.blue)
                    MetricTile(title: "Energia", value: check?.energyMorning.map { "\($0)/10" } ?? "—", icon: "bolt.fill", color: PivotTheme.amber)
                }
                if store.locked {
                    EmptyCard(title: "Storico da ripristinare", message: "Apri Impostazioni e recupera il backup per tornare a registrare le attività.", icon: "lock.shield")
                }
                if !calendar.hasAccess {
                    PivotCard {
                        ActionRow(title: "Collega la tua giornata", subtitle: "Leggi gli eventi dell'app Calendario, anche quelli Google.", icon: "calendar.badge.plus")
                        Button("Collega calendari") { Task { await calendar.requestAccess(); await calendar.refresh(settings: store.data.settings) } }.buttonStyle(PivotPrimaryButton())
                        if let error = calendar.error { Text(error).font(.caption).foregroundStyle(PivotTheme.amber) }
                    }
                }
                if PivotDate.calendar.isDateInToday(day), let preferred = Planner.preferredEvent(items, data: store.data, now: Date()) {
                    focusCard(preferred)
                }
                NavigationLink { DayCheckInView(day: day, initial: check) } label: {
                    PivotCard { ActionRow(title: "Come stai oggi?", subtitle: check?.wakeTime.map { "Sveglia alle \(PivotDate.time($0)) · aggiorna il tuo check-in" } ?? "Segna la sveglia, l'energia e l'umore.", icon: "sun.max.fill") }
                }.buttonStyle(.plain)
                if dayEvents.contains(where: { $0.kind == .university }) { universityCard(dayEvents: dayEvents, attendance: attendance) }
                if !conflicts.isEmpty {
                    PivotCard(tint: PivotTheme.amber) {
                        Label("Orari da chiarire", systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(PivotTheme.amber)
                        Text("Questi impegni si sovrappongono: non sono un programma già risolto.").font(.subheadline).foregroundStyle(PivotTheme.muted)
                        ForEach(Array(conflicts.prefix(3).enumerated()), id: \.offset) { _, pair in
                            Text("\(PivotDate.time(pair.0.start)) \(pair.0.title) ↔ \(PivotDate.time(pair.1.start)) \(pair.1.title)").font(.caption).fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Se oggi non frequenti le lezioni, indicarlo qui le toglie dal programma di Pivot.").font(.caption).foregroundStyle(PivotTheme.muted)
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "La tua agenda", detail: "\(items.count) attività")
                    if items.isEmpty { EmptyCard(title: "Spazio alla tua giornata", message: "Qui compariranno i tuoi eventi. Puoi cambiare giorno o aggiornare il calendario.", icon: "calendar") }
                    ForEach(items) { event in
                        NavigationLink { detail(event) } label: { EventRow(event: event, record: store.data.records[event.id], day: day) }.buttonStyle(.plain)
                    }
                }
                PivotCard(tint: PivotTheme.blue) {
                    Label("Un passo alla volta", systemImage: "sparkles").font(.subheadline.weight(.semibold)).foregroundStyle(PivotTheme.blue)
                    Text(Planner.isStudyPriority(store.data, now: Date()) ? "Proteggi le ore di studio che non riesci a recuperare prima dell'esame. Gli impegni fissi restano protetti." : "Un'attività è saltata? Aprila e cerca un nuovo spazio. Non serve ricominciare tutta la giornata.").font(.subheadline).foregroundStyle(PivotTheme.muted)
                }
                if store.lastExternalBackup == nil {
                    Label("Configura una copia dei tuoi dati in Impostazioni.", systemImage: "externaldrive.badge.icloud").font(.caption).foregroundStyle(PivotTheme.amber)
                }
            }
            .navigationTitle("Pivot")
            .toolbar { Button { Task { await calendar.refresh(settings: store.data.settings) } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Aggiorna calendari") }
            .refreshable { await calendar.refresh(settings: store.data.settings) }
            .sheet(item: $finishedTutoring) { event in NavigationStack { detail(event) } }
        }
    }
    private func universityCard(dayEvents: [CalendarItem], attendance: Bool?) -> some View {
        PivotCard(tint: PivotTheme.blue) {
            Label("Università oggi", systemImage: "graduationcap.fill").font(.headline).foregroundStyle(PivotTheme.blue)
            Text(attendance == false ? "Oggi non frequenti: le lezioni restano consultabili, fuori dalle attività da fare." : "Le lezioni del calendario vanno distinte da quelle che hai deciso di seguire.").font(.subheadline).foregroundStyle(PivotTheme.muted)
            HStack(spacing: 10) {
                Button("Seguo le lezioni") { setAttendance(true) }.buttonStyle(PivotSecondaryButton())
                Button("Oggi non vado") { setAttendance(false) }.buttonStyle(PivotSecondaryButton())
            }.disabled(store.locked)
            if attendance == false {
                DisclosureGroup("Lezioni fuori programma") {
                    ForEach(dayEvents.filter { $0.kind == .university }) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title).font(.subheadline)
                            Text("\(event.timeSummary) · non prevista oggi").font(.caption).foregroundStyle(PivotTheme.muted)
                        }.padding(.vertical, 6)
                    }
                }.font(.subheadline)
            }
        }
    }
    private func setAttendance(_ attending: Bool) {
        let key = PivotDate.key(day)
        store.change { data in
            var check = data.checkIns[key] ?? DayCheckIn(id: key)
            check.universityAttendance = attending
            data.checkIns[key] = check
        }
    }
    private func focusCard(_ event: CalendarItem) -> some View {
        let status = store.data.records[event.id]?.status ?? .pending
        return PivotCard(tint: Color(pivotHex: event.colorHex)) {
            HStack {
                Label("Adesso / appena terminato", systemImage: event.kind.icon).font(.caption.weight(.semibold)).foregroundStyle(Color(pivotHex: event.colorHex))
                Spacer(); StatusPill(status: status)
            }
            Text(event.title).font(.system(.title2, design: .rounded, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            Label(event.timeSummary, systemImage: "clock").font(.subheadline).foregroundStyle(PivotTheme.muted)
            if status == .pending || status == .running {
                Button { toggle(event) } label: { Label(status == .running ? "Termina attività" : "Inizia attività", systemImage: status == .running ? "stop.fill" : "play.fill") }
                    .buttonStyle(PivotPrimaryButton()).disabled(event.isAllDay || store.locked)
            }
            NavigationLink { detail(event) } label: { Label("Dettagli e registrazione", systemImage: "slider.horizontal.3") }.buttonStyle(PivotSecondaryButton())
        }
    }
    private func toggle(_ event: CalendarItem) {
        var record = store.record(for: event)
        if record.status == .running {
            record.actualEnd = Date(); record.status = .completed
            if let start = record.actualStart { record.activeMinutes = max(0, Int(Date().timeIntervalSince(start) / 60)) }
        } else { record.actualStart = Date(); record.actualEnd = nil; record.status = .running }
        record.updatedAt = Date()
        if store.change({ $0.records[event.id] = record }), event.kind == .tutoring && record.status == .completed { finishedTutoring = event }
    }
    private func detail(_ event: CalendarItem) -> some View {
        EventDetailView(event: event, initial: store.record(for: event), rule: store.rule(for: event))
    }
}

struct DayCheckInView: View {
    @EnvironmentObject var store: PivotStore
    let day: Date
    @State private var check: DayCheckIn
    @State private var wake: Date
    @Environment(\.dismiss) var dismiss
    init(day: Date, initial: DayCheckIn?) {
        self.day = day
        _check = State(initialValue: initial ?? .init(id: PivotDate.key(day)))
        _wake = State(initialValue: initial?.wakeTime ?? PivotDate.calendar.date(bySettingHour: 7, minute: 45, second: 0, of: day)!)
    }
    var body: some View {
        PivotScreen {
            PivotHeader(title: "Come stai?", subtitle: DisplayDate.label(day).capitalized)
            PivotCard(tint: PivotTheme.amber) {
                Label("La tua mattina", systemImage: "sun.max.fill").font(.headline).foregroundStyle(PivotTheme.amber)
                DatePicker("Sveglia reale", selection: $wake, displayedComponents: .hourAndMinute)
                Button(check.wakeTime == nil ? "Registra questo orario" : "Aggiorna la sveglia") { check.wakeTime = wake }.buttonStyle(PivotSecondaryButton())
                Text(check.wakeTime.map { "Registrata alle \(PivotDate.time($0))" } ?? "L'orario non è ancora registrato.").font(.caption).foregroundStyle(PivotTheme.muted)
                RatingField(title: "Energia", value: $check.energyMorning)
                RatingField(title: "Umore", value: $check.moodMorning)
            }
            PivotCard(tint: PivotTheme.blue) {
                Label("La tua sera", systemImage: "moon.stars.fill").font(.headline).foregroundStyle(PivotTheme.blue)
                RatingField(title: "Energia", value: $check.energyEvening)
                RatingField(title: "Umore", value: $check.moodEvening)
            }
            PivotCard {
                SectionHeading(title: "Qualcosa da raccontare?")
                TextField("Come è andata, cosa ti ha aiutato…", text: $check.notes, axis: .vertical).lineLimit(4...10)
            }
            Button("Salva check-in") { if store.change({ $0.checkIns[check.id] = check }) { dismiss() } }.buttonStyle(PivotPrimaryButton()).disabled(store.locked)
        }.navigationTitle("Check-in")
    }
}
