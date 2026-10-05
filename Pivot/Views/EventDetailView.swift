import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct EventDetailView: View {
    @EnvironmentObject var store: PivotStore
    @EnvironmentObject var calendar: CalendarService
    private let sourceEvent: CalendarItem
    private var onSaved: (() -> Void)?
    var event: CalendarItem {
        Planner.effectiveEvents(calendar.events.filter { $0.id == sourceEvent.id || EventCoalescer.savedOccurrence(sourceEvent, $0) }, data: store.data).first { $0.id == sourceEvent.id || EventCoalescer.savedOccurrence(sourceEvent, $0) } ?? sourceEvent
    }
    @State private var record: EventRecord
    @State private var rule: EventRule
    @State private var message: String?
    @State private var suggestions: [RecoverySuggestion] = []
    @State private var studentName = ""
    @State private var selectedClientID: UUID? = nil
    @State private var lessonAmount = ""
    @State private var receivedAmount = ""
    @State private var received = false
    @State private var receiptDate = Date()
    @State private var importingPDF = false
    @State private var importingMaterial = false
    @State private var documentPreview: StudyDocument?
    @State private var editingLogistics = false
    @State private var loadedDraft = false
    @State private var savedFingerprint = ""
    @State private var skipChoice = false
    var linkedIncome: IncomeEntry? { store.data.income.first { $0.id == record.incomeID || $0.calendarEventID == event.id } }
    var selectedClient: Client? { store.data.clients.first { $0.id == selectedClientID } }
    @Environment(\.dismiss) private var dismiss

    init(event: CalendarItem, initial: EventRecord, rule: EventRule, onSaved: (() -> Void)? = nil) {
        self.sourceEvent = event
        self.onSaved = onSaved
        _record = State(initialValue: initial)
        _rule = State(initialValue: rule)
    }
    var body: some View {
        PivotScreen {
            hero
            registration
            if !event.notes.isEmpty {
                PivotCard {
                    DisclosureGroup { Text(event.notes).font(.subheadline).foregroundStyle(PivotTheme.muted).textSelection(.enabled).padding(.top, 10) } label: { Label("Il programma di questa attività", systemImage: "list.bullet.clipboard").font(.subheadline.weight(.semibold)) }
                }
            }
            if event.kind == .tutoring {
                PivotCard {
                    Label("Dove fai questa lezione?", systemImage: "mappin.and.ellipse").font(.headline)
                    Text(store.record(for: event).logistics?.place.label ?? "Luogo da confermare").font(.subheadline)
                    if let logistics = store.record(for: event).logistics {
                        if !logistics.address.isEmpty { Text(logistics.address).font(.caption).foregroundStyle(PivotTheme.muted) }
                        if logistics.travelConfirmed {
                            Text("Partenza: \(PivotDate.time(event.start.addingTimeInterval(-Double(logistics.travelBeforeMinutes) * 60)))").font(.subheadline).foregroundStyle(PivotTheme.accent)
                        }
                    }
                    Button("Conferma / modifica questa lezione") { editingLogistics = true }.buttonStyle(PivotSecondaryButton())
                }
            }
            if [.tutoring, .work].contains(event.kind) { tutoring }
            if event.kind == .study { studyMaterial }
            if event.kind == .workout {
                CardioFields(value: $record.cardio, title: event.title)
                NavigationLink { TrainingView(event: event) } label: { Label("Scheda e diario palestra", systemImage: "dumbbell.fill") }.buttonStyle(PivotSecondaryButton())
            }
            PivotCard {
                DisclosureGroup("Promemoria personali") {
                Label("Promemoria per questo evento", systemImage: "pin.fill").font(.headline)
                TextField("Materiale da portare, cose da ricordare…", text: Binding(get: { record.reminders ?? "" }, set: { record.reminders = $0 }), axis: .vertical).lineLimit(2...6)
                Text("Queste note valgono solo per questa occorrenza.").font(.caption).foregroundStyle(PivotTheme.muted)
                }
            }
            if event.kind == .meal { meal }
            reflection
            PivotCard {
                DisclosureGroup { rules.padding(.top, 12) } label: { Label("Regole e tragitto", systemImage: "arrow.triangle.branch").font(.subheadline.weight(.semibold)) }
            }
            if let message { Label(message, systemImage: "info.circle").font(.subheadline).foregroundStyle(PivotTheme.amber) }
            Button { finishEditing() } label: { Label("Salva attività", systemImage: "checkmark.circle.fill") }.buttonStyle(PivotPrimaryButton()).disabled(store.locked)
            if rule.flexibility != .fixed && !event.isAllDay {
                Button { findRecovery() } label: { Label("Trova uno spazio per recuperare", systemImage: "arrow.triangle.2.circlepath") }.buttonStyle(PivotSecondaryButton()).disabled(store.locked)
            }
            ForEach(suggestions) { suggestion in
                PivotCard(tint: PivotTheme.blue) {
                    Label("\(DisplayDate.label(suggestion.start, format: "EEE d MMM")) · \(PivotDate.time(suggestion.start))–\(PivotDate.time(suggestion.end))", systemImage: "calendar.badge.clock").font(.headline)
                    Text(suggestion.explanation).font(.subheadline).foregroundStyle(PivotTheme.muted)
                    Button("Usa questo spazio in Pivot") { Task { await choose(suggestion) } }.buttonStyle(PivotPrimaryButton())
                    Text("Il Calendario non cambia ora. La modifica comparirà nel Pivot Coach, dove potrai controllarla e confermarla separatamente.")
                        .font(.caption).foregroundStyle(PivotTheme.muted)
                }
            }
        }
        .navigationTitle("Attività")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Salva") { finishEditing() }.disabled(store.locked) } }
        .onAppear {
            let firstAppearance = !loadedDraft
            if firstAppearance {
                if let draft = store.data.activityDrafts?[event.id] {
                    // A notification supplies an explicit outcome; don't replace it with an old draft outcome.
                    let selectedOutcome = record.status
                    record = draft.record; rule = draft.rule; studentName = draft.studentName; selectedClientID = draft.clientID
                    lessonAmount = draft.lessonAmount; receivedAmount = draft.receivedAmount; received = draft.received; receiptDate = draft.receiptDate
                    if selectedOutcome != .pending { record.status = selectedOutcome }
                }
                loadedDraft = true; savedFingerprint = fingerprint
            }
            // A workout diary can change the timer while this detail is underneath it.
            if !firstAppearance, event.kind == .workout, let latest = store.data.records[event.id] {
                record.actualStart = latest.actualStart; record.actualEnd = latest.actualEnd
                record.activeMinutes = latest.activeMinutes; record.status = latest.status
            }
        }
        .task(id: fingerprint) {
            guard loadedDraft else { return }
            do { try await Task.sleep(nanoseconds: 800_000_000) } catch { return }
            persistDraft()
        }
        .onDisappear { persistDraft() }
        .confirmationDialog("Vuoi recuperare questa attività?", isPresented: $skipChoice, titleVisibility: .visible) {
            Button("Cerca un altro spazio") { findRecovery() }
            Button("Salta definitivamente") { if save() { closeAfterSaving() } }
            Button("Torna all’attività", role: .cancel) {}
        } message: { Text("Se la salti sparisce dall’agenda di Pivot, ma resta nello storico. Il Calendario non viene cancellato.") }
        .sheet(isPresented: $editingLogistics, onDismiss: {
            rule = store.rule(for: event)
            record.logistics = store.record(for: event).logistics
        }) { LessonLogisticsView(event: event) }
        .fileImporter(isPresented: $importingPDF, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url): Task { await attachPDF(url) }
            case .failure(let error): message = error.localizedDescription
            }
        }
        .sheet(item: $documentPreview) { document in
            if let url = try? store.studyPDFURL(document) { StudyPDFPreview(url: url, title: document.name) }
        }
    }
    private var hero: some View {
        PivotCard(tint: Color(calendarItem: event)) {
            HStack {
                Label(event.kind.label, systemImage: event.kind.icon).font(.subheadline.weight(.semibold)).foregroundStyle(Color.readableCalendar(event))
                Spacer(); StatusPill(status: record.status)
            }
            Text(event.title).font(.system(.title2, design: .rounded, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            Label(event.timeSummary, systemImage: "clock").font(.subheadline).foregroundStyle(PivotTheme.muted)
            Text(event.calendarTitle).font(.caption).foregroundStyle(PivotTheme.muted)
            if !event.location.isEmpty { Label(event.location, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(PivotTheme.muted) }
            if !event.isAllDay { DisclosureGroup("Timer facoltativo") { Button {
                if record.status == .running { record.actualEnd = Date(); record.status = .completed; updateMinutes() }
                else { record.actualStart = Date(); record.actualEnd = nil; record.status = .running }
                save()
            } label: { Label(record.status == .running ? "Termina attività" : "Inizia attività", systemImage: record.status == .running ? "stop.fill" : "play.fill") }
                .buttonStyle(PivotPrimaryButton()).disabled(store.locked)
                Text("Puoi segnare l’esito anche senza avviare il timer.").font(.caption).foregroundStyle(PivotTheme.muted)
            }.font(.caption) }
            if let start = record.actualStart { Text("Inizio reale \(PivotDate.time(start))" + (record.actualEnd.map { " · fine \(PivotDate.time($0))" } ?? "")).font(.caption).foregroundStyle(PivotTheme.muted) }
        }
    }
    private var registration: some View {
        PivotCard {
            SectionHeading(title: "Come è andata?")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { outcomeButtons }
                VStack(spacing: 8) { outcomeButtons }
            }
            if record.status != .pending && record.status != .running {
                Button("Azzera l'esito") { record.status = .pending }.font(.caption).foregroundStyle(PivotTheme.muted)
            }
            if let health = record.health {
                Label("Dati da Salute · \(ActivityTiming.duration(health.durationSeconds))", systemImage: "heart.text.square").font(.caption).foregroundStyle(PivotTheme.accent)
            }
            if let sleep = record.healthSleep, let seconds = sleep.durationSeconds {
                Label("Sonno da Salute · \(ActivityTiming.duration(seconds))", systemImage: "bed.double.fill").font(.caption).foregroundStyle(PivotTheme.accent)
            }
            DisclosureGroup("Orari reali e durata") {
            ClockField(title: "Inizio reale", value: $record.actualStart, fallback: event.start)
            ClockField(title: "Fine reale", value: $record.actualEnd, fallback: event.end)
            if let start = record.actualStart, let end = record.actualEnd, let seconds = ActivityTiming.seconds(start: start, end: end) {
                Text("Durata calcolata: \(ActivityTiming.duration(seconds))").font(.subheadline).foregroundStyle(PivotTheme.accent)
            }
            DurationField(title: "Tempo attivo (escluse pause)", seconds: Binding(get: { record.activeMinutes == 0 ? nil : record.activeMinutes * 60 }, set: { record.activeMinutes = ($0 ?? 0) / 60 }), maxHours: 48)
            Button("Usa la durata tra inizio e fine") { updateMinutes() }.font(.caption)
            Text("Inizio e fine calcolano la durata. Se hai fatto pause, puoi correggere il tempo attivo in ore e minuti.").font(.caption).foregroundStyle(PivotTheme.muted)
                .onChange(of: record.actualStart) { _, _ in updateMinutes() }
                .onChange(of: record.actualEnd) { _, _ in updateMinutes() }
            }.font(.subheadline)
            if record.status == .partial || record.status == .skipped {
                TextField("Cosa ti ha fermato?", text: $record.reason, axis: .vertical).lineLimit(2...5).padding(12).background(PivotTheme.raised, in: RoundedRectangle(cornerRadius: 12))
                Text("Racconta il motivo: ci aiuta ad adattare il programma.").font(.caption).foregroundStyle(PivotTheme.amber)
            }
            TextField("Note extra, difficoltà o progressi…", text: $record.notes, axis: .vertical).lineLimit(3...8).padding(12).background(PivotTheme.raised, in: RoundedRectangle(cornerRadius: 12))
            DisclosureGroup("Energia durante l’attività") { RatingField(title: "Energia", value: $record.energy) }.font(.subheadline)
        }
    }
    private var outcomeButtons: some View {
        ForEach([Completion.completed, .partial, .skipped], id: \.self) { status in
            Button { record.status = status } label: {
                Text(status.label).font(.subheadline.weight(.semibold)).padding(.vertical, 12).frame(maxWidth: .infinity)
                    .foregroundStyle(record.status == status ? PivotTheme.background : PivotTheme.muted)
                    .background(record.status == status ? PivotTheme.accent : PivotTheme.raised, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).accessibilityAddTraits(record.status == status ? .isSelected : [])
        }
    }
    private var meal: some View {
        PivotCard(tint: PivotTheme.amber) {
            Label("Il tuo pasto", systemImage: "fork.knife").font(.headline).foregroundStyle(PivotTheme.amber)
            RatingField(title: "Fame prima", value: $record.hungerBefore)
            RatingField(title: "Fame dopo", value: $record.hungerAfter)
            Picker("Piano rispettato", selection: Binding(get: { record.followedMeal.map { $0 ? 1 : 2 } ?? 0 }, set: { record.followedMeal = $0 == 0 ? nil : $0 == 1 })) {
                Text("Non indicato").tag(0); Text("Sì").tag(1); Text("No").tag(2)
            }
        }
    }
    private var reflection: some View {
        let labels: (String, String, String) = {
            switch event.kind {
            case .study: return ("Quali argomenti hai studiato?", "Esercizi riusciti, errori o dubbi", "Da cosa riparti la prossima volta?")
            case .workout: return ("Allenamento o cardio svolto", "Esercizi, durata e sensazioni", "Cosa adatti la prossima volta?")
            case .university, .exam: return ("Argomenti affrontati", "Cosa hai capito e cosa manca?", "Cosa devi ripassare?")
            case .tutoring: return ("Argomenti della ripetizione", "Come è andata allo studente?", "Cosa preparare per la prossima lezione?")
            case .work: return ("Lavoro svolto", "Risultato", "Prossimo passo")
            case .meal: return ("Cosa hai mangiato?", "Quantità e variazioni rispetto al piano", "Cosa ti aiuta per il prossimo pasto?")
            case .routine: return ("Cosa hai fatto nella routine?", "Minuti e ostacoli", "Cosa prepari per domani?")
            case .partner, .friends, .social: return ("Com'è andata l'uscita?", "Tempi reali e cambi di programma", "Vuoi ricordarti qualcosa?")
            default: return ("Cosa hai fatto?", "Risultato o cose rimaste da fare", "Prossimo passo")
            }
        }()
        return PivotCard {
            DisclosureGroup {
                TextField(labels.0, text: reflectionBinding(\.focus), axis: .vertical).lineLimit(2...4)
                TextField(labels.1, text: reflectionBinding(\.result), axis: .vertical).lineLimit(2...4)
                TextField(labels.2, text: reflectionBinding(\.nextStep), axis: .vertical).lineLimit(2...4)
            } label: { Label("Dettagli: \(event.kind.label)", systemImage: "text.bubble").font(.subheadline.weight(.semibold)) }
        }
    }
    private var studyMaterial: some View {
        PivotCard(tint: PivotTheme.blue) {
            Label("Materiale della sessione", systemImage: "doc.richtext").font(.headline).foregroundStyle(PivotTheme.blue)
            TextField("Obiettivi: cosa devi capire", text: studyBinding(\.objectives), axis: .vertical).lineLimit(2...5)
                .padding(12).background(PivotTheme.raised, in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier("study-objectives")
            TextField("Esercizi da svolgere e pagine", text: studyBinding(\.exercises), axis: .vertical).lineLimit(2...5)
                .padding(12).background(PivotTheme.raised, in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier("study-exercises")
            ForEach(record.study?.documents ?? []) { document in
                HStack {
                    Button {
                        do { _ = try store.studyPDFURL(document); documentPreview = document }
                        catch { message = error.localizedDescription }
                    } label: { Label(document.name, systemImage: "doc.fill").font(.subheadline).lineLimit(2) }
                    Spacer()
                    Button(role: .destructive) { removeDocument(document) } label: { Image(systemName: "minus.circle") }
                        .accessibilityLabel("Rimuovi allegato \(document.name)").disabled(store.locked || importingMaterial)
                }
            }
            Button { importingPDF = true } label: { Label(importingMaterial ? "Importazione del PDF…" : "Aggiungi PDF da File", systemImage: "plus.circle") }
                .buttonStyle(PivotSecondaryButton()).disabled(store.locked || importingMaterial || (record.study?.documents.count ?? 0) >= StudyFiles.maximumDocuments)
            Text("Fino a 6 PDF, massimo 10 MB ciascuno. Sono copiati in Pivot e inclusi nel backup completo (50 MB totali). I materiali che prepariamo in chat vanno salvati in File e importati qui.")
                .font(.caption).foregroundStyle(PivotTheme.muted)
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--study-material-test") {
                Button("Importa PDF di prova") {
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Scheda di prova.pdf")
                    let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 600))
                    let bytes = renderer.pdfData { context in
                        context.beginPage()
                        ("Scheda di prova Pivot" as NSString).draw(at: CGPoint(x: 25, y: 25), withAttributes: nil)
                    }
                    do { try bytes.write(to: url); Task { await attachPDF(url) } }
                    catch { message = error.localizedDescription }
                }.accessibilityIdentifier("import-study-fixture")
            }
            #endif
        }
    }
    private func studyBinding(_ path: WritableKeyPath<StudySession, String>) -> Binding<String> {
        Binding(get: { (record.study ?? StudySession())[keyPath: path] }, set: { value in
            var session = record.study ?? StudySession(); session[keyPath: path] = value; record.study = session
        })
    }
    private func attachPDF(_ url: URL) async {
        guard !importingMaterial, (record.study?.documents.count ?? 0) < StudyFiles.maximumDocuments else { return }
        importingMaterial = true
        defer { importingMaterial = false }
        do {
            let document = try await store.importStudyPDF(url)
            guard StudyFiles.documents(in: store.data).reduce(0, { $0 + $1.byteCount }) + document.byteCount <= StudyFiles.maximumLibraryBytes else { throw StudyFileError.libraryFull }
            var session = record.study ?? StudySession()
            session.documents.append(document)
            record.study = session
            // Store the material independently of an unfinished activity questionnaire.
            saveStudyMaterial()
        } catch { message = error.localizedDescription }
    }
    private func removeDocument(_ document: StudyDocument) {
        var session = record.study ?? StudySession()
        session.documents.removeAll { $0.id == document.id }
        record.study = session
        saveStudyMaterial()
    }
    private func saveStudyMaterial() {
        var saved = store.record(for: event)
        saved.study = record.study
        saved.snapshot = event
        saved.updatedAt = Date()
        if !store.change({ $0.records[event.id] = saved }) { message = "Materiale non salvato. Riprova prima di chiudere." }
    }
    private func reflectionBinding(_ path: WritableKeyPath<ActivityReflection, String>) -> Binding<String> {
        Binding(get: { (record.reflection ?? ActivityReflection())[keyPath: path] }, set: { value in
            var details = record.reflection ?? ActivityReflection(); details[keyPath: path] = value; record.reflection = details
        })
    }
    private var tutoring: some View {
        PivotCard(tint: PivotTheme.accent) {
            Label("Quanto hai guadagnato?", systemImage: "eurosign.circle.fill").font(.headline)
            if let entry = linkedIncome {
                Text("Lezione registrata: \(Money.display(entry.amountCents))").font(.subheadline)
                NavigationLink { IncomeDetailView(entryID: entry.id) } label: { Label(entry.outstandingCents > 0 ? "Registra il pagamento mancante" : "Vedi il pagamento", systemImage: "arrow.right.circle") }
                Text("Salvare ancora questa attività non aggiunge un secondo incasso.").font(.caption).foregroundStyle(PivotTheme.muted)
            } else {
                Picker(event.kind == .work ? "Cliente" : "Studente", selection: $selectedClientID) {
                    Text("Inserisci il nome").tag(nil as UUID?)
                    ForEach(store.data.clients) { Text($0.name).tag(Optional($0.id)) }
                }
                if selectedClient == nil { TextField(event.kind == .work ? "Nome cliente / lavoro" : "Nome dello studente", text: $studentName).textContentType(.name) }
                TextField("Importo concordato in euro (anche 0)", text: $lessonAmount).keyboardType(.decimalPad)
                Toggle("Ho già ricevuto un pagamento", isOn: $received)
                if received {
                    TextField("Euro ricevuti", text: $receivedAmount).keyboardType(.decimalPad)
                    DatePicker("Data incasso", selection: $receiptDate)
                }
                Text("Il conto sale solo per i soldi ricevuti. La parte non pagata resta in ‘Da incassare’. Salva quando hai indicato l'esito della lezione.").font(.caption).foregroundStyle(PivotTheme.muted)
                if record.tutoringAnswered == true { Text("Nessun compenso registrato per questa attività.").font(.caption) }
            }
        }
    }
    private var rules: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Gestione", selection: $rule.flexibility) { ForEach(EventFlexibility.allCases, id: \.self) { Text($0.label).tag($0) } }
            Picker("Tipo di attività", selection: Binding(get: { rule.kindOverride ?? event.kind }, set: { rule.kindOverride = $0 })) { ForEach(EventKind.allCases, id: \.self) { Text($0.label).tag($0) } }
            Picker("Priorità", selection: Binding(get: { rule.priority ?? EventContext.priority(event, data: store.data, now: Date()) }, set: { rule.priority = $0 })) {
                ForEach(EventPriority.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            if rule.flexibility == .compressible {
                Toggle("Puoi proporre di accorciarla", isOn: Binding(get: { rule.compressionApproved == true }, set: { rule.compressionApproved = $0 }))
                if rule.compressionApproved == true {
                    DurationField(title: "Durata minima che accetti", seconds: Binding(get: { rule.minimumMinutes * 60 }, set: { rule.minimumMinutes = max(5, ($0 ?? 300) / 60) }), maxHours: 12)
                }
            }
            DurationField(title: "Tragitto prima", seconds: Binding(get: { rule.travelBeforeMinutes * 60 }, set: { rule.travelBeforeMinutes = ($0 ?? 0) / 60 }), maxHours: 4)
            DurationField(title: "Tragitto dopo", seconds: Binding(get: { rule.travelAfterMinutes * 60 }, set: { rule.travelAfterMinutes = ($0 ?? 0) / 60 }), maxHours: 4)
            Toggle("Tempi di tragitto verificati", isOn: $rule.travelConfirmed)
            Text("Conferma anche quando il tragitto è zero. In palestra, cambio e doccia fanno parte dell'attività. Riduzioni e spostamenti richiedono la tua conferma.").font(.caption).foregroundStyle(PivotTheme.muted)
        }.font(.subheadline)
    }
    private func findRecovery() {
        guard rule.travelConfirmed else { message = "Prima conferma i tempi di tragitto. Non posso supporre che siano zero."; return }
        guard save() else { return }
        suggestions = Planner.recover(event, events: calendar.events, data: store.data, now: Date())
        if suggestions.isEmpty { message = "Non ho trovato uno spazio completo nei prossimi tre giorni. Verifica i tragitti e confrontiamoci su cosa puoi rimandare. Non ho tagliato altri eventi." }
    }
    private func updateMinutes() {
        if let start = record.actualStart, let end = record.actualEnd { record.activeMinutes = max(0, Int(end.timeIntervalSince(start) / 60)) }
    }
    @discardableResult private func save() -> Bool {
        if let start = record.actualStart, let end = record.actualEnd, ActivityTiming.seconds(start: start, end: end) == nil {
            message = "La fine reale deve essere successiva all'inizio. Controlla anche la data se l'attività supera mezzanotte."; return false
        }
        guard record.cardio?.isValid ?? true else { message = "Controlla i dati cardio: usa numeri validi e lascia vuoti quelli che non hai."; return false }
        if (record.status == .partial || record.status == .skipped) && record.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message = "Scrivi il motivo dell'attività parziale o saltata."; return false
        }
        let isLessonDone = [.tutoring, .work].contains(event.kind) && [.completed, .partial].contains(record.status)
        var client: Client?
        var cents: Int?
        var collected = 0
        if isLessonDone && linkedIncome == nil && !lessonAmount.isEmpty {
            guard let amount = Money.cents(from: lessonAmount) else { message = "Inserisci un importo valido."; return false }
            cents = amount
            let name = selectedClient?.name ?? studentName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard amount == 0 || !name.isEmpty else { message = "Indica lo studente per registrare il guadagno."; return false }
            client = selectedClient ?? Client(name: name, rateCents: 0)
            if received {
                guard let paid = Money.cents(from: receivedAmount), paid > 0, paid <= amount else { message = "L'incasso deve essere positivo e non superiore all'importo della lezione."; return false }
                collected = paid
            }
        }
        record.updatedAt = Date()
        record.snapshot = event
        var saved = record
        saved.logistics = store.record(for: event).logistics
        let ok = store.change { data in
            let previousStatus = data.records[event.id]?.status ?? .pending
            if let client, let cents { TutoringLedger.register(event: event, record: &saved, client: client, amountCents: cents, collectedCents: collected, paymentDate: receiptDate, data: &data) }
            data.records[event.id] = saved; data.rules[event.id] = rule
            if previousStatus != saved.status && saved.status != .pending {
                var coach = data.coachState
                coach.messages.append(.init(dayKey: PivotDate.key(event.start), role: .system, text: "\(event.title): \(saved.status.label)." + (saved.reason.isEmpty ? "" : " Motivo: \(saved.reason)")))
                data.coachState = coach
            }
        }
        if ok {
            record = saved
            savedFingerprint = fingerprint
            store.change { $0.activityDrafts?.removeValue(forKey: event.id) }
            if isLessonDone && saved.tutoringAnswered != true && linkedIncome == nil { message = "Attività salvata. Completa anche il compenso della ripetizione." }
        }
        return ok
    }
    private func finishEditing() {
        if record.status == .skipped { skipChoice = true }
        else if save() { closeAfterSaving() }
    }
    private func closeAfterSaving() { onSaved?(); dismiss() }
    private var draft: ActivityDraft {
        ActivityDraft(record: record, rule: rule, studentName: studentName, clientID: selectedClientID, lessonAmount: lessonAmount,
                      receivedAmount: receivedAmount, received: received, receiptDate: receiptDate)
    }
    private var fingerprint: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(draft).base64EncodedString()) ?? ""
    }
    private func persistDraft() {
        guard loadedDraft, fingerprint != savedFingerprint, !store.locked, !store.isRestoring else { return }
        let value = draft
        store.change { data in
            var drafts = data.activityDrafts ?? [:]; drafts[event.id] = value; data.activityDrafts = drafts
        }
        savedFingerprint = fingerprint
    }
    private func choose(_ suggestion: RecoverySuggestion) async {
        await calendar.refresh(settings: store.data.settings)
        guard let source = calendar.events.first(where: { $0.id == event.id || EventCoalescer.savedOccurrence(event, $0) }) else {
            message = "L'evento è cambiato o non è più disponibile. Aggiorna la giornata."; return
        }
        let move = PlanMove(source: source, proposedStart: suggestion.start, proposedEnd: suggestion.end)
        guard slotIsAvailable(move) else { message = "Questo spazio non è più libero. Cerca una nuova proposta."; return }
        if store.change({ data in
            data.moves.removeAll { !$0.syncedToCalendar && $0.source.id == source.id }
            data.moves.append(move)
            var coach = data.coachState
            coach.pendingCalendarChanges.removeAll { $0.move.source.id == source.id }
            coach.pendingCalendarChanges.append(PendingCalendarChange(move: move, optionTitle: "Recupero scelto dall’attività"))
            coach.messages.append(.init(dayKey: PivotDate.key(Date()), role: .system, text: "Recupero applicato in Pivot: \(source.title). In attesa della conferma finale per il Calendario."))
            data.coachState = coach
            if var saved = data.records[source.id], saved.status == .skipped { saved.status = .pending; data.records[source.id] = saved }
        }) {
            message = "Proposta applicata in Pivot. Il Calendario non è cambiato: confermala dal Pivot Coach."
            suggestions = []
            savedFingerprint = fingerprint
            store.change { $0.activityDrafts?.removeValue(forKey: event.id) }
            closeAfterSaving()
        }
    }
    private func slotIsAvailable(_ move: PlanMove) -> Bool {
        guard rule.travelConfirmed, move.proposedStart > Date() else { return false }
        let occupiedStart = move.proposedStart.addingTimeInterval(-Double(rule.travelBeforeMinutes) * 60)
        let occupiedEnd = move.proposedEnd.addingTimeInterval(Double(rule.travelAfterMinutes) * 60)
        return !Planner.effectiveEvents(calendar.events, data: store.data).contains { item in
            guard item.id != event.id, !item.isAllDay else { return false }
            let other = store.rule(for: item)
            if !item.location.isEmpty && !other.travelConfirmed && PivotDate.key(item.start) == PivotDate.key(move.proposedStart) { return true }
            return item.start.addingTimeInterval(-Double(other.travelBeforeMinutes) * 60) < occupiedEnd
                && item.end.addingTimeInterval(Double(other.travelAfterMinutes) * 60) > occupiedStart
        }
    }
}
