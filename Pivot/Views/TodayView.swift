import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: PivotStore
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var health: HealthService
    @State private var day = Date()
    @State private var showDecisions = false
    @State private var showHealth = false
    private var check: DayCheckIn? { store.data.checkIns[PivotDate.key(day)] }
    private var items: [CalendarItem] {
        Planner.plannedEvents(calendar.events, data: store.data).filter { $0.occurs(on: day) && store.data.records[$0.id]?.status != .skipped }
    }
    private var active: [CalendarItem] { items.filter { ![Completion.completed, .partial].contains(store.data.records[$0.id]?.status ?? .pending) } }
    private var finished: [CalendarItem] { items.filter { [Completion.completed, .partial].contains(store.data.records[$0.id]?.status ?? .pending) } }
    private var focused: CalendarItem? {
        PivotDate.calendar.isDateInToday(day) ? Planner.preferredEvent(active, data: store.data, now: Date()) : active.first
    }
    private var decisions: [EventDecision] { (store.data.decisions ?? []).filter { PivotDate.calendar.isDate($0.date, inSameDayAs: day) } }
    var body: some View {
        NavigationStack {
            PivotScreen {
                DaySelector(day: $day)
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(PivotDate.calendar.isDateInToday(day) ? "Il prossimo passo" : DisplayDate.label(day, format: "EEEE").capitalized)
                            .font(.system(.title, design: .rounded, weight: .bold))
                        Text(DisplayDate.label(day, format: "d MMMM") + " · \(finished.count)/\(items.count) attività segnate").font(.caption).foregroundStyle(PivotTheme.muted)
                    }
                    Spacer()
                    NavigationLink { CoachView() } label: { Image(systemName: "bubble.left.and.bubble.right.fill").font(.title3).padding(12).background(PivotTheme.accent.opacity(0.1), in: Circle()) }
                        .accessibilityLabel("Parla con Pivot").accessibilityIdentifier("open-pivot-coach")
                }
                if store.locked {
                    EmptyCard(title: "Storico da ripristinare", message: "Recupera il backup nelle Impostazioni. I dati originali sono protetti.", icon: "lock.shield")
                } else if !calendar.hasAccess {
                    PivotCard {
                        ActionRow(title: "Collega il calendario", subtitle: "Tutti i tuoi impegni, con i loro colori.", icon: "calendar.badge.plus")
                        Button("Consenti calendari") { Task { await calendar.requestAccess(); await calendar.refresh(settings: store.data.settings) } }.buttonStyle(PivotPrimaryButton())
                        if let error = calendar.error { Text(error).font(.caption).foregroundStyle(PivotTheme.amber) }
                    }
                } else if let focused { focusCard(focused) }
                else { EmptyCard(title: active.isEmpty ? "Per oggi hai segnato tutto" : "Un po’ di spazio per te", message: "Puoi rivedere le attività e completare il diario quando vuoi.", icon: "checkmark.circle") }

                HStack(spacing: 12) {
                    NavigationLink { DayCheckInView(day: day, initial: check) } label: {
                        Label(check?.energyMorning.map { "Energia \($0)/10" } ?? "Come stai?", systemImage: "sun.max")
                    }.buttonStyle(.plain)
                    Spacer()
                    Button { showDecisions = true } label: {
                        Label(decisions.isEmpty ? "Nessun dubbio" : "Da decidere · \(decisions.count)", systemImage: decisions.isEmpty ? "checkmark.circle" : "questionmark.bubble")
                            .foregroundStyle(decisions.isEmpty ? PivotTheme.muted : PivotTheme.amber)
                    }.accessibilityIdentifier("decision-inbox")
                }.font(.caption.weight(.semibold)).padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "In arrivo", detail: "\(active.filter { $0.id != focused?.id }.count)")
                    ForEach(Array(active.filter { $0.id != focused?.id }.prefix(3))) { event in
                        NavigationLink { detail(event) } label: { EventRow(event: event, record: store.data.records[event.id], day: day) }.buttonStyle(.plain)
                    }
                    if active.filter({ $0.id != focused?.id }).count > 3 {
                        DisclosureGroup("Mostra le altre attività") {
                            ForEach(Array(active.filter { $0.id != focused?.id }.dropFirst(3))) { event in
                                NavigationLink { detail(event) } label: { EventRow(event: event, record: store.data.records[event.id], day: day) }.buttonStyle(.plain)
                            }
                        }.font(.subheadline)
                    }
                    if active.isEmpty { Text("Nessuna attività da compilare.").font(.subheadline).foregroundStyle(PivotTheme.muted) }
                }
                if !finished.isEmpty {
                    DisclosureGroup("Già segnate · \(finished.count)") {
                        VStack(spacing: 12) {
                            ForEach(finished) { event in
                                NavigationLink { detail(event) } label: { EventRow(event: event, record: store.data.records[event.id], day: day) }.buttonStyle(.plain)
                            }
                        }.padding(.top, 12)
                    }.font(.subheadline.weight(.semibold)).foregroundStyle(PivotTheme.muted)
                }
                if items.contains(where: { $0.kind == .university }) || store.data.checkIns[PivotDate.key(day)]?.universityAttendance == false {
                    DisclosureGroup("Lezioni universitarie di oggi") {
                        HStack {
                            Button("Le seguo") { attendance(true) }.buttonStyle(PivotSecondaryButton())
                            Button("Non vado") { attendance(false) }.buttonStyle(PivotSecondaryButton())
                        }.padding(.top, 10)
                    }.font(.subheadline).foregroundStyle(PivotTheme.muted)
                }
                Button { showHealth = true } label: {
                    Label(store.data.settings.healthEnabled == true ? "Salute e attività rilevate" : "Collega Salute e Apple Watch", systemImage: "heart.text.square")
                }.font(.caption).foregroundStyle(PivotTheme.muted)
                if let sync = calendar.lastRefresh {
                    Label("Calendario aggiornato alle \(PivotDate.time(sync))", systemImage: "arrow.triangle.2.circlepath").font(.caption2).foregroundStyle(PivotTheme.muted).accessibilityIdentifier("calendar-updated")
                }
                if calendar.isRefreshing { ProgressView().accessibilityIdentifier("calendar-loading") }
            }
            .navigationTitle("Pivot")
            .toolbar { Button { Task { await calendar.refresh(settings: store.data.settings) } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Aggiorna calendari") }
            .refreshable { await calendar.refresh(settings: store.data.settings); await health.refresh(store: store, events: calendar.events, force: true) }
            .sheet(isPresented: $showDecisions) { DecisionInboxView() }
            .sheet(isPresented: $showHealth) { healthSheet }
        }
    }
    private func focusCard(_ event: CalendarItem) -> some View {
        let isPast = event.end <= Date(), status = store.data.records[event.id]?.status ?? .pending
        return PivotCard(tint: Color(calendarItem: event)) {
            HStack {
                Label(isPast ? "Com’è andata?" : (event.start > Date() ? "Il prossimo impegno" : "Adesso"), systemImage: event.kind.icon)
                    .font(.caption.weight(.semibold)).foregroundStyle(Color.readableCalendar(event))
                Spacer(); StatusPill(status: status)
            }
            Text(event.title).font(.system(.title2, design: .rounded, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            Label(event.timeSummary, systemImage: "clock").font(.subheadline).foregroundStyle(PivotTheme.muted)
            if !event.location.isEmpty { Label(event.location, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(PivotTheme.muted) }
            NavigationLink { CoachView(contextEventID: event.id) } label: {
                Label(isPast ? "Racconta a Pivot" : "Apri attività", systemImage: isPast ? "bubble.left.fill" : "arrow.right")
            }.buttonStyle(PivotPrimaryButton())
            NavigationLink { detail(event) } label: { Text("Dettagli e registrazione").font(.caption).foregroundStyle(PivotTheme.muted) }
                .accessibilityIdentifier("activity-detail")
        }.overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 3).fill(Color(calendarItem: event)).frame(width: 5).padding(.vertical, 24) }
    }
    private var healthSheet: some View {
        NavigationStack {
            PivotScreen {
                PivotHeader(title: "Salute", subtitle: "Dati disponibili, senza registrare tutto a mano")
                Text(health.status).font(.subheadline).foregroundStyle(PivotTheme.muted)
                Button("Collega / aggiorna Salute") { Task { await health.connect(store: store, events: calendar.events) } }.buttonStyle(PivotPrimaryButton()).disabled(health.isRefreshing || store.locked)
                if let sleep = health.sleep(on: day) {
                    PivotCard { Label("Sonno rilevato", systemImage: "bed.double.fill"); Text(ActivityTiming.duration(sleep.durationSeconds)).font(.title2.bold()); Text("\(PivotDate.shortDate(sleep.start)) \(PivotDate.time(sleep.start)) – \(PivotDate.time(sleep.end))").font(.caption) }
                }
                ForEach(health.workouts.filter { PivotDate.calendar.isDate($0.start, inSameDayAs: day) }) { workout in
                    let matches = HealthImport.candidates(workout, events: items)
                    PivotCard {
                        Label(workout.type == "walk" ? "Camminata" : (workout.type == "hike" ? "Escursione" : "Allenamento"), systemImage: "figure.walk")
                        Text("\(PivotDate.time(workout.start)) · \(ActivityTiming.duration(workout.durationSeconds))").font(.subheadline)
                        let linked = items.first { store.data.records[$0.id]?.health?.id == workout.id }
                        Text(linked.map { "Collegato all’evento: \($0.title)" } ?? (matches.isEmpty ? "Attività generale: non conta come allenamento programmato." : "Collegamento non confermato: controlla i dettagli dell’attività.")).font(.caption).foregroundStyle(PivotTheme.muted)
                    }
                }
            }.navigationTitle("Salute").toolbar { Button("Chiudi") { showHealth = false } }
        }.presentationDragIndicator(.visible)
    }
    private func detail(_ event: CalendarItem) -> some View { EventDetailView(event: event, initial: store.record(for: event), rule: store.rule(for: event)) }
    private func attendance(_ value: Bool) {
        store.change { data in
            let key = PivotDate.key(day); var check = data.checkIns[key] ?? DayCheckIn(id: key)
            check.universityAttendance = value; data.checkIns[key] = check
        }
    }
}

struct DayCheckInView: View {
    @EnvironmentObject var store: PivotStore
    @EnvironmentObject var health: HealthService
    @EnvironmentObject var calendar: CalendarService
    @Environment(\.dismiss) var dismiss
    let day: Date
    @State private var check: DayCheckIn
    @State private var wake: Date
    init(day: Date, initial: DayCheckIn?) {
        self.day = day
        _check = State(initialValue: initial ?? .init(id: PivotDate.key(day)))
        _wake = State(initialValue: initial?.wakeTime ?? PivotDate.calendar.date(bySettingHour: 7, minute: 45, second: 0, of: day)!)
    }
    var body: some View {
        PivotScreen {
            PivotHeader(title: "Come stai?", subtitle: DisplayDate.label(day).capitalized)
            PivotCard(tint: PivotTheme.amber) {
                Label("La tua mattina", systemImage: "sun.max.fill").font(.headline)
                ClockField(title: "Sveglia reale", value: $check.wakeTime, fallback: wake)
                RatingField(title: "Energia", value: $check.energyMorning)
                RatingField(title: "Umore", value: $check.moodMorning)
            }
            PivotCard(tint: PivotTheme.blue) {
                Label("Sonno", systemImage: "bed.double.fill").font(.headline)
                if check.sleep?.importedFromHealth == true {
                    Text("Da Salute · \(check.sleep?.durationSeconds.map(ActivityTiming.duration) ?? "—")").font(.title3.weight(.semibold))
                    if let start = check.sleep?.bedtime { Text("\(PivotDate.shortDate(start)) · \(PivotDate.time(start))").font(.caption).foregroundStyle(PivotTheme.muted) }
                } else { Text("Puoi leggere i dati da Salute oppure inserire quelli che vedi sull’Apple Watch.").font(.caption).foregroundStyle(PivotTheme.muted) }
                Button("Leggi da Salute") { Task { await health.connect(store: store, events: calendar.events); if let latest = store.data.checkIns[check.id] { check.sleep = latest.sleep; check.healthWakeTime = latest.healthWakeTime; if check.wakeTime == nil { check.wakeTime = latest.wakeTime } } } }.buttonStyle(PivotSecondaryButton()).disabled(health.isRefreshing)
                DisclosureGroup("Inserisci / correggi manualmente") {
                    ClockField(title: "A letto: data e ora", value: sleepBinding(\.bedtime), fallback: day.addingTimeInterval(-8 * 3600))
                    DurationField(title: "Tempo dormito", seconds: sleepBinding(\.durationSeconds), maxHours: 24)
                    IntegerField(title: "Punteggio sonno (0–100)", value: sleepBinding(\.score))
                    TextField("Qualità (facoltativa)", text: sleepBinding(\.quality))
                    IntegerField(title: "Numero di risvegli", value: sleepBinding(\.awakenings))
                    DurationField(title: "Interruzioni", seconds: sleepBinding(\.interruptionSeconds), maxHours: 24)
                }.font(.subheadline)
            }
            PivotCard {
                DisclosureGroup("La tua sera e le note") {
                    RatingField(title: "Energia sera", value: $check.energyEvening)
                    RatingField(title: "Umore sera", value: $check.moodEvening)
                    TextField("Cosa ti ha aiutato, cosa ti ha bloccato…", text: $check.notes, axis: .vertical).lineLimit(3...8)
                }.font(.subheadline)
            }
            Button("Salva check-in") {
                if let sleep = check.sleep, !(sleep.score.map { (0...100).contains($0) } ?? true) || !(sleep.awakenings.map { (0...1000).contains($0) } ?? true) {
                    store.error = "Controlla punteggio sonno e risvegli."; return
                }
                if store.change({ $0.checkIns[check.id] = check }) { dismiss() }
            }.buttonStyle(PivotPrimaryButton()).disabled(store.locked)
        }.navigationTitle("Check-in")
    }
    private func sleepBinding<T>(_ path: WritableKeyPath<SleepRecord, T>) -> Binding<T> {
        Binding(get: { (check.sleep ?? SleepRecord())[keyPath: path] }, set: { value in
            var sleep = check.sleep ?? SleepRecord(); sleep[keyPath: path] = value; sleep.importedFromHealth = false; check.sleep = sleep
        })
    }
}
