import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: PivotStore
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var health: HealthService
    @EnvironmentObject var agenda: AgendaService
    @State private var day = Self.initialDay
    private static var initialDay: Date {
        #if DEBUG && targetEnvironment(simulator)
        // The weekly-payment fixture records Monday and edits Wednesday, regardless
        // of the wall-clock day on which CI runs. Real devices always open today.
        if ProcessInfo.processInfo.arguments.contains("--payment-schedule-test") {
            return PivotDate.calendar.date(byAdding: .day, value: 2, to: StudentPayments.week(containing: Date()).start)!
        }
        #endif
        return Date()
    }
    @State private var showDecisions = false
    @State private var showHealth = false
    @State private var healthMessage: String?
    @State private var quickRecord: EventRecord?
    @State private var lessonToConfirm: CalendarItem?
    private var check: DayCheckIn? { store.data.checkIns[PivotDate.key(day)] }
    private var items: [CalendarItem] {
        agenda.planned.filter { $0.occurs(on: day) && store.data.records[$0.id]?.status != .skipped }
    }
    private var active: [CalendarItem] { items.filter { ![Completion.completed, .partial].contains(store.data.records[$0.id]?.status ?? .pending) } }
    private var finished: [CalendarItem] { items.filter { [Completion.completed, .partial].contains(store.data.records[$0.id]?.status ?? .pending) } }
    private var focused: CalendarItem? {
        PivotDate.calendar.isDateInToday(day) ? Planner.preferredPlannedEvent(active, data: store.data, now: Date()) : active.first
    }
    private var decisions: [EventDecision] { (store.data.decisions ?? []).filter { PivotDate.calendar.isDate($0.date, inSameDayAs: day) } }
    var body: some View {
        let items = self.items, active = self.active, finished = self.finished, focused = self.focused
        let remaining = active.filter { $0.id != focused?.id }
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
                    NavigationLink { CoachView() } label: {
                        VStack(spacing: 3) { Image(systemName: "bubble.left.and.bubble.right.fill").font(.title3); Text("Pivot").font(.caption2.weight(.semibold)) }.padding(12).background(PivotTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
                    }
                        .accessibilityLabel("Parla con Pivot").accessibilityIdentifier("open-pivot-coach")
                }
                if store.isLoading {
                    ProgressView("Carico il tuo storico…")
                } else if store.locked {
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
                if (store.data.workoutReviews ?? []).contains(where: { !$0.resolved && !$0.dismissed }) {
                    Button { showHealth = true } label: { Label("Salute ha un’attività da collegare", systemImage: "heart.text.square") }.buttonStyle(PivotSecondaryButton())
                }
                if store.data.actualWorkoutDraft != nil {
                    NavigationLink { CoachView() } label: { Label("Registrazione della giornata da completare", systemImage: "square.and.pencil") }.buttonStyle(PivotSecondaryButton())
                }
                let endOfDay = PivotDate.calendar.date(byAdding: .day, value: 1, to: PivotDate.calendar.startOfDay(for: day))!
                let duePayments = agenda.paymentDues.filter { $0.date.map { $0 < endOfDay } ?? false }
                ForEach(Array(duePayments.prefix(3))) { due in
                    if let client = store.data.clients.first(where: { $0.id == due.clientID }) {
                        NavigationLink { ClientDetailView(client: client) } label: {
                            PivotCard(tint: PivotTheme.amber) {
                                Label("\(due.clientName): \(Money.display(due.amountCents)) da ricevere", systemImage: "eurosign.circle")
                                PaymentDueLabel(due: due)
                            }
                        }.buttonStyle(.plain)
                    }
                }
                if let lesson = LessonLogistics.pendingEffective(events: agenda.effective, data: store.data, now: Date()).first {
                    Button { lessonToConfirm = lesson } label: { Label("Conferma luogo: " + lesson.title, systemImage: "person.2.fill") }.buttonStyle(PivotSecondaryButton())
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "La tua agenda", detail: "\(remaining.count)")
                    Text("Spunta ciò che hai fatto, anche fuori dall’orario previsto.").font(.caption).foregroundStyle(PivotTheme.muted)
                    ForEach(Array(remaining.prefix(3))) { event in
                        agendaRow(event)
                    }
                    if remaining.count > 3 {
                        DisclosureGroup("Mostra le altre attività") {
                            ForEach(Array(remaining.dropFirst(3))) { event in
                                agendaRow(event)
                            }
                        }.font(.subheadline)
                    }
                    if active.isEmpty { Text("Nessuna attività da compilare.").font(.subheadline).foregroundStyle(PivotTheme.muted) }
                }
                if !finished.isEmpty {
                    DisclosureGroup("Già segnate · \(finished.count)") {
                        VStack(spacing: 12) {
                            ForEach(finished) { event in
                                agendaRow(event)
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
                    Label(store.data.settings.healthEnabled == true ? "Salute e attività rilevate" : "Collega app Salute", systemImage: "heart.text.square")
                }.font(.caption).foregroundStyle(PivotTheme.muted).accessibilityIdentifier("open-health")
                if let sync = calendar.lastRefresh {
                    Label("Calendario aggiornato alle \(PivotDate.time(sync))", systemImage: "arrow.triangle.2.circlepath").font(.caption2).foregroundStyle(PivotTheme.muted).accessibilityIdentifier("calendar-updated")
                }
                if calendar.isRefreshing { ProgressView().accessibilityIdentifier("calendar-loading") }
            }
            .navigationTitle("Pivot")
            .toolbar { Button { Task { await calendar.refresh(settings: store.data.settings) } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Aggiorna calendari") }
            .refreshable { await calendar.refresh(settings: store.data.settings); await health.refresh(store: store, events: calendar.events, force: true, recheckHeartRate: true) }
            .sheet(isPresented: $showDecisions) { DecisionInboxView() }
            .sheet(isPresented: $showHealth) { healthSheet }
            .sheet(item: $lessonToConfirm) { event in LessonLogisticsView(event: event) }
            .sheet(item: $quickRecord) { record in NavigationStack { EventDetailView(event: record.snapshot, initial: record, rule: store.rule(for: record.snapshot)) }.presentationDragIndicator(.visible) }
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
            Button { complete(event) } label: { Label("Attività svolta", systemImage: "square") }.font(.subheadline).foregroundStyle(PivotTheme.accent).frame(minHeight: 44)
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
                if health.lastAttempt?.message != health.status {
                    Text(health.status).font(.subheadline).foregroundStyle(PivotTheme.muted)
                }
                if let attempt = health.lastAttempt {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ultimo tentativo · \(DisplayDate.label(attempt.finishedAt ?? attempt.startedAt, format: "d MMMM yyyy · HH:mm"))")
                            .font(.caption.weight(.semibold)).foregroundStyle(PivotTheme.muted)
                            .accessibilityIdentifier("health-last-attempt-time")
                        Text(attempt.message).font(.caption)
                            .foregroundStyle(attempt.outcome == .failed || attempt.outcome == .partial ? PivotTheme.amber : PivotTheme.muted)
                            .accessibilityIdentifier("health-last-attempt-status")
                    }
                }
                Button(store.data.settings.healthEnabled == true ? "Aggiorna dati da Salute" : "Collega app Salute") { Task { await health.connect(store: store, events: calendar.events) } }.buttonStyle(PivotPrimaryButton()).disabled(health.isRefreshing || health.isConnecting || store.locked)
                if let report = health.lastReport {
                    PivotCard(tint: PivotTheme.blue) {
                        Label("Ultima lettura salvata da Salute", systemImage: "clock.arrow.circlepath").font(.headline)
                        Text(DisplayDate.label(report.readAt, format: "d MMMM yyyy · HH:mm"))
                            .font(.caption).foregroundStyle(PivotTheme.muted)
                            .accessibilityIdentifier("health-last-successful-read")
                        Text("Letti \(report.workoutSamples) allenamenti e \(report.sleepDays) notti negli ultimi 7 giorni.").font(.subheadline)
                        if report.appliedChanges == 0 {
                            Text("Nessuna modifica nuova in Pivot.").font(.caption).foregroundStyle(PivotTheme.muted)
                        } else {
                            if report.workoutsApplied > 0 { Text("Allenamenti collegati al diario: \(report.workoutsApplied)").font(.caption) }
                            if report.sleepDaysApplied > 0 { Text("Check-in del sonno aggiornati: \(report.sleepDaysApplied)").font(.caption) }
                            if report.sleepEventsCompleted > 0 { Text("Eventi sonno completati: \(report.sleepEventsCompleted)").font(.caption) }
                        }
                        Text(report.pendingDecisions == 0 ? "Nessuna attività da chiarire." : "Da decidere: \(report.pendingDecisions) attività.")
                            .font(.caption.weight(.semibold)).foregroundStyle(report.pendingDecisions == 0 ? PivotTheme.muted : PivotTheme.amber)
                        Text("Pivot legge soltanto: non scrive dati nell’app Salute.").font(.caption).foregroundStyle(PivotTheme.muted)
                    }.accessibilityIdentifier("health-refresh-report")
                }
                if let healthMessage { Text(healthMessage).font(.caption).foregroundStyle(PivotTheme.amber).accessibilityIdentifier("health-action-message") }
                if let sleep = health.sleep(on: day) {
                    PivotCard {
                        Label("Da Salute · sonno", systemImage: "bed.double.fill").font(.headline).foregroundStyle(PivotTheme.blue)
                        Text(ActivityTiming.duration(sleep.durationSeconds)).font(.title2.bold())
                        Text("\(PivotDate.shortDate(sleep.start)) \(PivotDate.time(sleep.start)) – \(PivotDate.time(sleep.end))").font(.caption)
                        Text(store.data.checkIns[PivotDate.key(day)]?.sleep?.importedFromHealth == true ? "Usato da Pivot nel check-in e per la sveglia reale." : "Letto, ma non ha modificato il check-in di questa giornata.")
                            .font(.caption).foregroundStyle(PivotTheme.muted)
                    }
                }
                let dayWorkouts = health.workouts.filter { PivotDate.calendar.isDate($0.start, inSameDayAs: day) }
                ForEach(dayWorkouts) { workout in
                    healthWorkoutCard(workout)
                }
                let otherPending = (store.data.workoutReviews ?? []).filter {
                    !$0.resolved && !$0.dismissed && !PivotDate.calendar.isDate($0.workout.start, inSameDayAs: day)
                }
                if !otherPending.isEmpty {
                    SectionHeading(title: "Altre attività da decidere", detail: "\(otherPending.count)")
                    ForEach(otherPending) { review in healthWorkoutCard(review.workout) }
                }
            }.navigationTitle("Salute").toolbar { Button("Chiudi") { showHealth = false } }
        }.presentationDragIndicator(.visible)
    }
    private func healthWorkoutCard(_ workout: HealthWorkoutSummary) -> some View {
        let linked = agenda.planned.first { store.data.records[$0.id]?.health?.id == workout.id }
        let review = (store.data.workoutReviews ?? []).first { $0.id == workout.id && !$0.resolved && !$0.dismissed }
        return PivotCard {
            Label("Da Salute · \(healthWorkoutName(workout))", systemImage: "heart.text.square.fill").font(.headline).foregroundStyle(PivotTheme.blue)
            Text("\(PivotDate.shortDate(workout.start)) · \(PivotDate.time(workout.start))–\(PivotDate.time(workout.end)) · \(ActivityTiming.duration(workout.durationSeconds))").font(.subheadline)
            HStack(spacing: 12) {
                if let km = workout.distanceKM { Text(String(format: "%.2f km", km)) }
                if let kcal = workout.activeCalories { Text("\(Int(kcal.rounded())) kcal") }
                if let bpm = workout.averageBPM { Text("\(bpm) bpm") }
            }.font(.caption).foregroundStyle(PivotTheme.muted)
            if let linked, let record = store.data.records[linked.id] {
                Text("Usato da Pivot: ‘\(linked.title)’ è stato completato con questi orari reali.").font(.caption).foregroundStyle(PivotTheme.accent)
                if let timing = CalendarSynchronization.actualTiming(for: record, event: linked), CalendarSynchronization.needsCalendarUpdate(timing, event: linked) {
                    Button("Usa questi orari anche nel Calendario") { Task { await syncHealthRecord(record, event: linked) } }
                        .buttonStyle(PivotSecondaryButton()).disabled(store.locked)
                } else {
                    Text("Il Calendario ha già gli stessi orari.").font(.caption).foregroundStyle(PivotTheme.muted)
                }
            } else if let review {
                Label("Scegli a quale allenamento corrisponde", systemImage: "questionmark.circle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(PivotTheme.amber)
                ForEach(agenda.planned.filter { review.eventIDs.contains($0.id) }) { event in
                    Button("È ‘\(event.title)’ · collega e aggiorna Calendario") { Task { await confirmHealthReview(review, event: event) } }
                        .buttonStyle(PivotSecondaryButton()).disabled(store.locked)
                }
                Button("Non corrisponde a un allenamento programmato") { dismissHealthReview(review) }
                    .font(.caption).disabled(store.locked)
            } else {
                Text("Non usato da Pivot: attività generale, senza corrispondenza sicura nel programma.").font(.caption).foregroundStyle(PivotTheme.muted)
            }
        }
    }
    private func healthWorkoutName(_ workout: HealthWorkoutSummary) -> String {
        switch workout.type {
        case "walk": return "Camminata"
        case "hike": return "Escursione"
        case "run": return "Corsa"
        case "cycle": return "Bici"
        case "strength", "functional": return "Allenamento di forza"
        case "hiit": return "HIIT"
        default: return "Allenamento"
        }
    }
    private func dismissHealthReview(_ review: WorkoutReview) {
        if store.change({ data in
            if let index = data.workoutReviews?.firstIndex(where: { $0.id == review.id }) { data.workoutReviews?[index].dismissed = true }
        }) { healthMessage = "Attività lasciata come dato generale di Salute. Nessun evento è stato modificato." }
    }
    private func confirmHealthReview(_ review: WorkoutReview, event: CalendarItem) async {
        var record: EventRecord?
        guard store.change({ data in
            HealthImport.apply(review.workout, to: event, data: &data)
            guard data.records[event.id]?.health?.id == review.id else { return }
            if let index = data.workoutReviews?.firstIndex(where: { $0.id == review.id }) { data.workoutReviews?[index].resolved = true }
            record = data.records[event.id]
        }), let record else {
            healthMessage = "Non ho modificato nulla: l’attività aveva già un esito manuale da conservare."
            return
        }
        await syncHealthRecord(record, event: event)
    }
    private func syncHealthRecord(_ record: EventRecord, event: CalendarItem) async {
        do {
            if let updated = try await calendar.applyActualTimes(for: record, event: event, data: store.data) {
                store.change { data in
                    guard var saved = data.records[event.id] else { return }
                    saved.snapshot = updated; data.records[event.id] = saved
                }
                healthMessage = "Dati Salute collegati e orari aggiornati nel Calendario."
            } else {
                healthMessage = "Dati Salute collegati. Il Calendario aveva già gli stessi orari."
            }
        } catch {
            healthMessage = "Dati Salute salvati in Pivot, ma Calendario invariato: \(error.localizedDescription)"
        }
    }
    private func detail(_ event: CalendarItem) -> some View { EventDetailView(event: event, initial: store.record(for: event), rule: store.rule(for: event)) }
    private func agendaRow(_ event: CalendarItem) -> some View {
        let record = store.data.records[event.id], done = [Completion.completed, .partial].contains(record?.status ?? .pending)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(event.agendaStart(on: day)).font(.subheadline.weight(.semibold))
                if !event.isAllDay { Text(event.agendaEnd(on: day)).font(.caption).foregroundStyle(PivotTheme.muted) }
                Button { if done { quickRecord = store.record(for: event) } else { complete(event) } } label: {
                    Image(systemName: done ? "checkmark.square.fill" : "square").font(.title3).foregroundStyle(done ? PivotTheme.accent : PivotTheme.muted).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(done ? "Rivedi esito di \(event.title)" : "Segna svolta \(event.title)").accessibilityIdentifier("quick-complete-" + event.id)
            }.frame(width: 47, alignment: .leading)
            NavigationLink { detail(event) } label: { EventRow(event: event, record: record, day: day).eventCard }.buttonStyle(.plain).opacity(done ? 0.52 : 1)
        }
    }
    private func complete(_ event: CalendarItem) {
        guard !store.locked else { return }
        var record = store.record(for: event)
        EventAutofill.complete(&record, event: event)
        if [.tutoring, .work, .workout].contains(event.kind) || event.title.lowercased().contains("sonno") {
            record.status = .completed; quickRecord = record; return
        }
        record.status = .completed; record.updatedAt = Date()
        store.change { data in
            data.records[event.id] = record
            var coach = data.coachState; coach.messages.append(.init(dayKey: PivotDate.key(day), role: .user, text: "Ho svolto ‘\(event.title)’ come previsto. Gli orari suggeriti dal calendario restano correggibili.")); data.coachState = coach
        }
    }
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
    private var automaticSleep: Bool { check.sleep?.importedFromHealth == true }
    private var automaticWake: Bool { automaticSleep && check.healthWakeTime != nil && (check.wakeTime == nil || check.wakeTime == check.healthWakeTime) }
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
                if automaticWake, let value = check.healthWakeTime {
                    HStack { Text("Sveglia da Salute"); Spacer(); Text(PivotDate.time(value)).font(.headline) }
                    DisclosureGroup("Correggi soltanto se il dato non è giusto") {
                        ClockField(title: "Sveglia reale", value: $check.wakeTime, fallback: value)
                    }.font(.caption)
                } else {
                    ClockField(title: "Sveglia reale", value: $check.wakeTime, fallback: wake)
                }
                RatingField(title: "Energia", value: $check.energyMorning, metric: .energy, referenceDate: day)
                RatingField(title: "Stanchezza", value: $check.fatigueMorning, metric: .fatigue, referenceDate: day)
                RatingField(title: "Umore", value: $check.moodMorning, metric: .mood, referenceDate: day)
            }
            PivotCard(tint: PivotTheme.blue) {
                Label("Sonno", systemImage: "bed.double.fill").font(.headline)
                if check.sleep?.importedFromHealth == true {
                    Text("Da Salute · \(check.sleep?.durationSeconds.map(ActivityTiming.duration) ?? "—")").font(.title3.weight(.semibold))
                    if let sleep = check.sleep, let start = sleep.bedtime {
                        Text("\(PivotDate.shortDate(start)) \(PivotDate.time(start)) – \(check.healthWakeTime.map(PivotDate.time) ?? "—")").font(.caption).foregroundStyle(PivotTheme.muted)
                        if let awakenings = sleep.awakenings { Text("Risvegli rilevati: \(awakenings)").font(.caption).foregroundStyle(PivotTheme.muted) }
                    }
                    Text("Non devi reinserire orari, durata o risvegli.").font(.caption).foregroundStyle(PivotTheme.accent)
                } else if store.data.settings.healthEnabled == true {
                    Text("Pivot aggiorna il sonno automaticamente da Salute. Per questa notte non ci sono ancora dati leggibili.").font(.caption).foregroundStyle(PivotTheme.muted)
                } else {
                    Text("Collega app Salute per compilare automaticamente orari, durata e risvegli.").font(.caption).foregroundStyle(PivotTheme.muted)
                }
                Button(store.data.settings.healthEnabled == true ? "Aggiorna ora da Salute" : "Collega app Salute") {
                    Task { await refreshHealth() }
                }.buttonStyle(PivotSecondaryButton()).disabled(health.isRefreshing || health.isConnecting)
                DisclosureGroup(automaticSleep ? "Correggi manualmente soltanto se serve" : "Inserisci manualmente") {
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
                    RatingField(title: "Energia sera", value: $check.energyEvening, metric: .energy, referenceDate: day)
                    RatingField(title: "Stanchezza sera", value: $check.fatigueEvening, metric: .fatigue, referenceDate: day)
                    RatingField(title: "Umore sera", value: $check.moodEvening, metric: .mood, referenceDate: day)
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
            .task {
                if store.data.settings.healthEnabled == true && !automaticSleep { await refreshHealth() }
            }
    }
    private func sleepBinding<T>(_ path: WritableKeyPath<SleepRecord, T>) -> Binding<T> {
        Binding(get: { (check.sleep ?? SleepRecord())[keyPath: path] }, set: { value in
            var sleep = check.sleep ?? SleepRecord(); sleep[keyPath: path] = value; sleep.importedFromHealth = false; check.sleep = sleep
        })
    }
    private func refreshHealth() async {
        if store.data.settings.healthEnabled == true { await health.refresh(store: store, events: calendar.events, force: true, recheckHeartRate: true) }
        else { await health.connect(store: store, events: calendar.events) }
        if let latest = store.data.checkIns[check.id] {
            let wasAutomatic = check.wakeTime == nil || check.wakeTime == check.healthWakeTime
            check.sleep = latest.sleep
            check.healthWakeTime = latest.healthWakeTime
            if wasAutomatic { check.wakeTime = latest.wakeTime }
        }
    }
}
