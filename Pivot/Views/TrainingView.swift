import SwiftUI
import UniformTypeIdentifiers
import UIKit
import UserNotifications

private enum WorkoutSetAppearance: String, CaseIterable, Identifiable {
    case warmup, working, backoff, superset, dropSet, failure
    var id: String { rawValue }
    init(_ set: TrainingSet) {
        if set.reachesFailure { self = .failure; return }
        switch set.resolvedKind {
        case .warmup: self = .warmup
        case .working: self = .working
        case .backoff: self = .backoff
        case .superset: self = .superset
        case .dropSet: self = .dropSet
        }
    }
    var badge: String {
        switch self {
        case .warmup: return "W"
        case .working: return "1"
        case .backoff: return "B"
        case .superset: return "S"
        case .dropSet: return "D"
        case .failure: return "F"
        }
    }
    var name: String {
        switch self {
        case .warmup: return "Warm-up"
        case .working: return "Working"
        case .backoff: return "Back-off"
        case .superset: return "Superset"
        case .dropSet: return "Drop set"
        case .failure: return "Failure"
        }
    }
    var color: Color {
        switch self {
        case .warmup: return Color(red: 0.93, green: 0.66, blue: 0.08)
        case .working: return .gray
        case .backoff: return .purple
        case .superset: return .teal
        case .dropSet: return Color(red: 0.15, green: 0.62, blue: 0.92)
        case .failure: return .red
        }
    }
}

private struct WorkoutSetOptionsTarget: Identifiable {
    let id: UUID
}

struct TrainingView: View {
    @EnvironmentObject var store: PivotStore
    var event: CalendarItem? = nil
    @State private var importing = false
    @State private var busy = false
    @State private var pendingPlan: TrainingPlan?
    @State private var preview: StudyDocument?
    @State private var message: String?
    @State private var editingPlan: TrainingPlan?
    @State private var newPlan = false
    @State private var reportDate = Date()
    @State private var reportURL: URL?
    @State private var showingReport = false
    var library: TrainingLibrary { store.data.training ?? TrainingLibrary() }
    var body: some View {
        PivotScreen {
            PivotHeader(title: "Il tuo allenamento", subtitle: "La scheda del personal, i tuoi carichi, i tuoi progressi.")
            if let event { Label(event.title, systemImage: "calendar").font(.subheadline) }
            if let plan = library.activePlan {
                PivotCard(tint: PivotTheme.accent) {
                    Label("Scheda attiva", systemImage: "doc.richtext").font(.caption).foregroundStyle(PivotTheme.accent)
                    Text(plan.payload.name).font(.title2.bold())
                    if plan.document != nil { Button("Apri PDF originale della scheda") { preview = plan.document }.buttonStyle(PivotSecondaryButton()) }
                    Button("Modifica scheda · indicazioni del coach") { editingPlan = plan }.buttonStyle(PivotSecondaryButton()).disabled(store.locked).accessibilityIdentifier("edit-training-plan")
                    if !(plan.revisions ?? []).isEmpty {
                        Text("\(plan.revisions?.count ?? 0) modifiche salvate nell'app. Il PDF originale non viene riscritto.").font(.caption).foregroundStyle(PivotTheme.muted)
                        NavigationLink("Versioni e ripristino della scheda") { TrainingRevisionsView(planID: plan.id) }
                    }
                }
                ForEach(TrainingDayOrder.corrected(plan.payload.days)) { day in
                    NavigationLink {
                        TrainingSessionView(plan: plan, day: day, library: library, event: event)
                    } label: {
                        PivotCard {
                            ActionRow(title: day.name, subtitle: "\(day.exercises.count) esercizi · apri il diario", icon: "dumbbell.fill")
                            Text(day.exercises.map(\.name).joined(separator: " · ")).font(.caption).foregroundStyle(PivotTheme.muted).lineLimit(3)
                        }
                    }.buttonStyle(.plain).disabled(store.locked).accessibilityIdentifier("workout-day-\(day.id)")
                }
            } else {
                EmptyCard(title: "Pronto per la tua scheda", message: "Quando il personal te la manda, condividila qui in chat. La rielaboriamo in un PDF Pivot: importalo e trovi gli esercizi nell'ordine corretto. Non ci sono esercizi o carichi inventati.", icon: "doc.badge.plus")
            }
            ExerciseGalleryView()
            Button("Crea nuova scheda / nuovo obiettivo") { newPlan = true }.buttonStyle(PivotSecondaryButton()).disabled(store.locked || library.plans.count >= 6)
            Button { importing = true } label: { Label(busy ? "Leggo la scheda…" : "Importa nuova scheda PDF", systemImage: "square.and.arrow.down") }.buttonStyle(PivotPrimaryButton()).disabled(store.locked || busy || library.plans.count >= 6)
            Text("Solo PDF preparati per Pivot. L'importazione mostra un riepilogo da confermare e non cancella gli allenamenti precedenti.").font(.caption).foregroundStyle(PivotTheme.muted)
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--workout-controls-test") {
                Button("Verifica controlli allenamento") {
                    Task {
                        do { try await WorkoutControlsFixture.verify(); message = "Controlli allenamento verificati" }
                        catch { message = "Controlli non validi: \(error.localizedDescription)" }
                    }
                }.accessibilityIdentifier("workout-controls-fixture")
            }
            if ProcessInfo.processInfo.arguments.contains("--report-test") {
                Button("Genera report di prova") {
                    do { message = "PDF verificato: \(try TrainingReportFixture.export()) pagine" }
                    catch { message = "PDF non valido: \(error.localizedDescription)" }
                }.accessibilityIdentifier("report-fixture")
            }
            if ProcessInfo.processInfo.arguments.contains("--training-test") {
                Button("Importa scheda di prova") { Task { await importTestPDF() } }.accessibilityIdentifier("import-training-fixture")
            }
            #endif
            if library.plans.count > 1 {
                PivotCard {
                    Picker("Scheda da usare", selection: Binding(get: { library.activePlanID }, set: { id in store.change { $0.training?.activePlanID = id } })) {
                        ForEach(library.plans) { Text($0.payload.name).tag(Optional($0.id)) }
                    }
                }
            }
            if !library.sessions.isEmpty {
                PivotCard {
                    Text("Riepilogo settimanale per il PT").font(.headline)
                    DatePicker("Settimana contenente", selection: $reportDate, displayedComponents: .date)
                    Text("Esporta solo gli allenamenti svolti da lunedì a domenica, anche se ne hai fatti soltanto uno o due.").font(.caption).foregroundStyle(PivotTheme.muted)
                    Button("Prepara PDF della settimana") {
                        Task {
                            do { reportURL = try await store.trainingWeekExportURL(containing: reportDate); showingReport = true }
                            catch { message = error.localizedDescription }
                        }
                    }.buttonStyle(PivotSecondaryButton()).accessibilityIdentifier("export-training-week")
                }
                SectionHeading(title: "Ultimi allenamenti")
                ForEach(library.sessions.sorted { $0.start > $1.start }.prefix(20)) { session in
                    NavigationLink {
                        TrainingSessionView(session: session, tips: library.tips, event: nil)
                    } label: {
                        PivotCard { ActionRow(title: session.dayName, subtitle: "\(PivotDate.shortDate(session.start)) · \(session.end == nil ? "in corso" : "terminato")", icon: "clock.arrow.circlepath") }
                    }.buttonStyle(.plain)
                }
            }
            if let message { Text(message).font(.subheadline).foregroundStyle(PivotTheme.amber).accessibilityIdentifier("training-message") }
        }.navigationTitle("Palestra")
            .sheet(isPresented: $showingReport) { if let reportURL { TrainingReportPreview(url: reportURL) } }
            .sheet(item: $editingPlan) { TrainingPlanEditor(plan: $0) }
            .sheet(isPresented: $newPlan) { TrainingPlanEditor() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
                switch result {
                case .success(let url): Task {
                    busy = true; defer { busy = false }
                    do { pendingPlan = try await store.importTrainingPDF(url) }
                    catch { message = error.localizedDescription }
                }
                case .failure(let error): message = error.localizedDescription
                }
            }
            .sheet(item: $preview) { document in
                if let url = try? store.studyPDFURL(document) { StudyPDFPreview(url: url, title: document.name) }
            }
            .sheet(item: $pendingPlan) { plan in
                NavigationStack {
                    PivotScreen {
                        PivotHeader(title: "Conferma la scheda", subtitle: plan.payload.name)
                        ForEach(TrainingDayOrder.corrected(plan.payload.days)) { day in
                            PivotCard {
                                Text(day.name).font(.headline)
                                ForEach(day.exercises) { exercise in
                                    Text("\(exercise.name) · \(exercise.sets) × \(exercise.reps) · recupero \(ActivityTiming.duration(exercise.restSeconds))").font(.subheadline)
                                }
                            }
                        }
                        Button("Usa questa scheda") {
                            do { try store.installTrainingPlan(plan); pendingPlan = nil; message = "Scheda pronta. Scegli un allenamento." }
                            catch { message = error.localizedDescription; pendingPlan = nil }
                        }.buttonStyle(PivotPrimaryButton())
                        Button("Annulla") { pendingPlan = nil }.buttonStyle(PivotSecondaryButton())
                    }.navigationTitle("Importazione")
                }
            }
    }
    #if DEBUG && targetEnvironment(simulator)
    private func importTestPDF() async {
        do {
            let layoutTest = ProcessInfo.processInfo.arguments.contains("--training-layout-test")
            var exercises = [TrainingExercise(id: "test-exercise", name: layoutTest ? "Bench Press" : "Esercizio test",
                                              sets: layoutTest ? 4 : 1, reps: "8", restSeconds: 60, coachNotes: "Nota test")]
            if layoutTest {
                exercises.append(TrainingExercise(id: "test-squat", name: "Barbell Squat", sets: 4, reps: "6", restSeconds: 120,
                                                  coachNotes: "Dati di prova", catalogID: "Barbell_Squat"))
            }
            let payload = TrainingPlanPayload(formatVersion: 1, name: "Scheda TEST", days: [TrainingDay(id: "test-a", name: "Giorno test", exercises: exercises)])
            let block = try TrainingPDFFormat.encodedBlock(payload)
            let lines = block.components(separatedBy: "\n")
            let encoded = lines[1]
            var wrapped: [String] = []
            var cursor = encoded.startIndex
            while cursor < encoded.endIndex {
                let to = encoded.index(cursor, offsetBy: 48, limitedBy: encoded.endIndex) ?? encoded.endIndex
                wrapped.append(String(encoded[cursor..<to])); cursor = to
            }
            let text = "Scheda TEST, non personale\n" + lines[0] + "\n" + wrapped.joined(separator: "\n") + "\n" + lines[2]
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 800))
            let bytes = renderer.pdfData { context in
                context.beginPage()
                (text as NSString).draw(in: CGRect(x: 25, y: 25, width: 550, height: 750), withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: UIColor.black])
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Scheda-TEST.pdf")
            try bytes.write(to: url)
            pendingPlan = try await store.importTrainingPDF(url)
        } catch { message = error.localizedDescription }
    }
    #endif
}

struct TrainingSessionView: View {
    @EnvironmentObject var store: PivotStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: TrainingSession
    @State private var tips: [String: String]
    @State private var message: String?
    @State private var export: URL?
    @State private var sharing = false
    @State private var hasStarted: Bool
    @State private var selectingExercise = false
    @State private var replacementID: String?
    @State private var applyToPlan = false
    @State private var revealedSetID: UUID?
    @State private var setOptions: WorkoutSetOptionsTarget?
    var focusSetID: UUID? = nil
    let event: CalendarItem?
    init(plan: TrainingPlan, day: TrainingDay, library: TrainingLibrary, event: CalendarItem?) {
        self.event = event
        let existing = library.sessions.first { $0.calendarEventID == event?.id && event != nil && $0.planID == plan.id }
            ?? library.sessions.filter { $0.end == nil && $0.planID == plan.id && $0.dayName == day.name && $0.calendarEventID == nil && event == nil }.sorted { $0.start > $1.start }.first
        _session = State(initialValue: Self.markingSetOrigins(existing ?? library.makeSession(plan: plan, day: day, eventID: event?.id)))
        _tips = State(initialValue: library.tips)
        _hasStarted = State(initialValue: existing != nil)
    }
    init(session: TrainingSession, tips: [String: String], event: CalendarItem?, focusSetID: UUID? = nil) {
        _session = State(initialValue: Self.markingSetOrigins(session)); _tips = State(initialValue: tips); self.event = event
        _hasStarted = State(initialValue: true)
        self.focusSetID = focusSetID
    }
    var body: some View {
        ScrollViewReader { proxy in
        PivotScreen {
            PivotHeader(title: session.dayName, subtitle: "Segna solo quello che fai davvero.")
            PivotCard(tint: PivotTheme.accent) {
                Text(!hasStarted ? "Pronto per iniziare" : session.end == nil ? "Allenamento in corso" : "Allenamento terminato").font(.headline)
                if hasStarted {
                    ClockField(title: "Inizio", value: Binding(get: { session.start }, set: { if let date = $0 { session.start = date } }), fallback: session.start)
                    ClockField(title: "Fine", value: $session.end, fallback: Date())
                } else {
                    Button("Inizia allenamento") { session.start = Date(); hasStarted = true; save() }.buttonStyle(PivotPrimaryButton()).disabled(store.locked)
                }
                if hasStarted && session.end == nil {
                    Button("Termina allenamento") { WorkoutRuntime.finishRest(&session); session.end = Date(); save() }.buttonStyle(PivotPrimaryButton())
                    Button("Attiva controlli sulla schermata di blocco") {
                        guard save() else { return }
                        Task {
                            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                            await WorkoutRuntime.update(session, start: true)
                            if !WorkoutRuntime.status.isEmpty { message = WorkoutRuntime.status }
                        }
                    }.buttonStyle(PivotSecondaryButton())
                }
            }
            if session.rest != nil && session.end == nil { restCard }
            ForEach(session.exercises.indices, id: \.self) { index in
                exerciseCard(index)
            }
            PivotCard {
                Toggle("Aggiorna anche la scheda per le prossime volte", isOn: $applyToPlan)
                Text(applyToPlan ? "Il cambio aggiorna anche il giorno corrispondente della scheda, conservando la versione precedente." : "Aggiunte e sostituzioni valgono solo per questo allenamento.").font(.caption).foregroundStyle(PivotTheme.muted)
                Button("Aggiungi esercizio extra") { replacementID = nil; selectingExercise = true }.buttonStyle(PivotSecondaryButton()).disabled(!hasStarted || store.locked).accessibilityIdentifier("add-workout-exercise")
                if !hasStarted { Text("Inizia l'allenamento per aggiungere o sostituire un esercizio; puoi anche modificare la scheda prima di iniziare.").font(.caption).foregroundStyle(PivotTheme.muted) }
            }
            PivotCard { TextField("Note sull'allenamento…", text: $session.notes, axis: .vertical).lineLimit(2...5) }
            Button("Salva allenamento") { save() }.buttonStyle(PivotPrimaryButton()).disabled(store.locked)
            Button("Esporta per il personal") {
                guard save() else { return }
                Task {
                    do { export = try await store.trainingExportURL(session); sharing = true }
                    catch { message = error.localizedDescription }
                }
            }.buttonStyle(PivotSecondaryButton()).disabled(store.locked || !hasStarted)
            if let message { Text(message).font(.caption).foregroundStyle(PivotTheme.amber) }
        }.navigationTitle("Allenamento")
            .sheet(isPresented: $selectingExercise) {
                ExercisePickerView { exercise in changeExercise(exercise); selectingExercise = false }
            }
            .onDisappear { save() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { save() } }
            .sheet(isPresented: $sharing) { if let export { TrainingReportPreview(url: export) } }
            .sheet(item: $setOptions) { target in
                if let location = setLocation(target.id) {
                    setOptionsSheet(exerciseIndex: location.exercise, setIndex: location.set)
                }
            }
            .onChange(of: session.exercises) { _, _ in if hasStarted { save() } }
            .onChange(of: session.notes) { _, _ in if hasStarted { save() } }
            .onChange(of: session.start) { _, _ in if hasStarted { save() } }
            .onChange(of: session.end) { _, _ in if hasStarted { save() } }
            .onChange(of: tips) { _, _ in save() }
            .onChange(of: store.data.updatedAt) { _, _ in
                if let latest = store.data.training?.sessions.first(where: { $0.id == session.id }), latest.updatedAt > session.updatedAt { session = Self.markingSetOrigins(latest) }
            }
            .task {
                if let focusSetID {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    proxy.scrollTo(focusSetID, anchor: .center); WorkoutRuntime.focusedSet[session.id] = focusSetID
                }
            }
        }
    }
    private func exerciseCard(_ index: Int) -> some View {
        let exercise = session.exercises[index].exercise
        let previous = (store.data.training ?? TrainingLibrary()).previous(exerciseID: exercise.id, before: session.start, excluding: session.id)
        let hasCompletedSets = session.exercises[index].sets.contains(where: \.done)
        return PivotCard {
            HStack(alignment: .top, spacing: 12) {
                NavigationLink { ExerciseStatisticsView(exercise: exercise, current: hasStarted ? session : nil) } label: {
                    HStack(spacing: 12) {
                    ExerciseThumbnail(exercise: exercise).frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(index + 1). \(exercise.name)").font(.headline)
                        Text("\(exercise.sets) serie × \(exercise.reps) · recupero \(ActivityTiming.duration(exercise.restSeconds))")
                            .font(.caption).foregroundStyle(PivotTheme.muted)
                        Text("Cronologia e progressi").font(.caption.weight(.semibold)).foregroundStyle(PivotTheme.blue)
                    }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("workout-exercise-statistics-\(exercise.id)")
                Spacer(minLength: 4)
                Menu {
                    Button("Cambia esercizio", systemImage: "arrow.triangle.2.circlepath") {
                        replacementID = exercise.id
                        selectingExercise = true
                    }
                    .disabled(!hasStarted || hasCompletedSets || store.locked)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .frame(width: 40, height: 40)
                        .background(PivotTheme.raised, in: Circle())
                }
                .accessibilityLabel("Opzioni esercizio")
            }
            if hasCompletedSets {
                Text("Hai già registrato delle serie: per conservare ciò che hai fatto, aggiungi il nuovo esercizio come extra.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
            }
            if !exercise.coachNotes.isEmpty {
                Label(exercise.coachNotes, systemImage: "quote.bubble.fill")
                    .font(.caption).foregroundStyle(PivotTheme.accent)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(PivotTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            if let previous {
                Text("Ultima volta · " + previous.sets.filter(\.done).map { TrainingReports.performance($0, exercise: previous.exercise) }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(PivotTheme.blue)
            } else { Text("Prima registrazione: nessun carico preimpostato.").font(.caption).foregroundStyle(PivotTheme.muted) }
            if !hasCompletedSets {
                DisclosureGroup("Impostazioni esercizio") {
                    Toggle("Isometria · registra secondi", isOn: Binding(get: { session.exercises[index].exercise.usesDuration }, set: { session.exercises[index].exercise.isometric = $0 }))
                    if session.exercises[index].exercise.usesDuration {
                        Toggle("Durata separata per lato", isOn: Binding(get: { session.exercises[index].exercise.separateSides == true }, set: { session.exercises[index].exercise.separateSides = $0 }))
                        Toggle("Zavorra", isOn: Binding(get: { session.exercises[index].exercise.weightedHold == true }, set: { session.exercises[index].exercise.weightedHold = $0 }))
                    }
                }
                .font(.caption.weight(.semibold))
            }
            if exercise.usesDuration {
                Text("Inserisci la durata effettiva; i secondi non diventano kg né ripetizioni.").font(.caption).foregroundStyle(PivotTheme.muted)
            }
            workoutSetColumnHeadings(exercise)
            VStack(spacing: 6) {
                ForEach(session.exercises[index].sets) { set in
                    if let setIndex = session.exercises[index].sets.firstIndex(where: { $0.id == set.id }) {
                        workoutSetRow(exerciseIndex: index, setIndex: setIndex, exercise: exercise)
                    }
                }
            }
            Menu {
                Button("W · Warm-up") { addWarmup(exerciseIndex: index) }
                    .accessibilityIdentifier("add-warmup-\(exercise.id)")
                Button("Working") { addWorkingSet(exerciseIndex: index) }
                    .accessibilityIdentifier("add-working-\(exercise.id)")
            } label: {
                Label("Aggiungi serie", systemImage: "plus").font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(PivotTheme.raised, in: RoundedRectangle(cornerRadius: 10))
            }
            .accessibilityIdentifier("add-set-\(exercise.id)")
            .disabled(!hasStarted || store.locked || session.exercises[index].sets.count >= 60)
            if let tip = tips[exercise.id], !tip.isEmpty {
                Label(tip, systemImage: "pin.fill").font(.caption).foregroundStyle(PivotTheme.blue)
            }
            DisclosureGroup("Note e promemoria") {
                TextField("Note di questa sessione…", text: $session.exercises[index].notes, axis: .vertical).lineLimit(2...5)
                TextField("Promemoria per le prossime volte…", text: Binding(get: { tips[exercise.id] ?? "" }, set: { tips[exercise.id] = $0 }), axis: .vertical).lineLimit(2...5)
                    .padding(12).background(PivotTheme.raised, in: RoundedRectangle(cornerRadius: 12))
                Text("Le note descrivono questa sessione. I promemoria restano salvati per i prossimi allenamenti.").font(.caption).foregroundStyle(PivotTheme.muted)
            }.font(.caption.weight(.semibold))
        }
    }
    private func workoutSetColumnHeadings(_ exercise: TrainingExercise) -> some View {
        HStack(spacing: 6) {
            Text("SET").frame(width: 40)
            if !exercise.usesDuration || exercise.weightedHold == true {
                Text("KG").frame(maxWidth: .infinity)
            }
            if exercise.usesDuration && exercise.separateSides == true {
                Text("SX · S").frame(maxWidth: .infinity)
                Text("DX · S").frame(maxWidth: .infinity)
            } else {
                Text(exercise.usesDuration ? "SECONDI" : "REPS").frame(maxWidth: .infinity)
            }
            Image(systemName: "checkmark").frame(width: 44)
            Color.clear.frame(width: 28, height: 1)
        }
        .font(.caption2.weight(.semibold)).foregroundStyle(PivotTheme.muted)
        .padding(.horizontal, 6).accessibilityHidden(true)
    }
    private func workoutSetRow(exerciseIndex: Int, setIndex: Int, exercise: TrainingExercise) -> some View {
        let set = session.exercises[exerciseIndex].sets[setIndex]
        let canRemove = canRemoveSet(exerciseIndex: exerciseIndex, setIndex: setIndex)
        let isRevealed = revealedSetID == set.id
        return ZStack(alignment: .trailing) {
            if canRemove && isRevealed {
                Button(role: .destructive) {
                    withAnimation(.easeOut(duration: 0.18)) { revealedSetID = nil }
                    removeSet(exerciseIndex: exerciseIndex, setIndex: setIndex)
                } label: {
                    Image(systemName: "trash.fill").foregroundStyle(.white)
                        .frame(width: 72).frame(maxHeight: .infinity)
                }
                .buttonStyle(.plain).contentShape(Rectangle())
                .background(Color.red).zIndex(1).accessibilityLabel("Elimina serie aggiunta")
                .accessibilityIdentifier("delete-set-\(exercise.id)-\(setIndex)")
            }
            HStack(spacing: 6) {
                setTypeMenu(exerciseIndex: exerciseIndex, setIndex: setIndex)
                    .frame(width: 40)
                if !exercise.usesDuration || exercise.weightedHold == true {
                    DecimalField(title: exercise.usesDuration ? "Zavorra" : "Carico", unit: "kg",
                                 value: weightBinding(exerciseIndex: exerciseIndex, setIndex: setIndex),
                                 identifier: "weight-\(exercise.id)-\(setIndex)", compact: true)
                        .frame(maxWidth: .infinity)
                }
                if exercise.usesDuration {
                    if exercise.separateSides == true {
                        IntegerField(title: "Sinistra · s", value: $session.exercises[exerciseIndex].sets[setIndex].leftSeconds,
                                     identifier: "left-\(exercise.id)-\(setIndex)", compact: true).frame(maxWidth: .infinity)
                        IntegerField(title: "Destra · s", value: $session.exercises[exerciseIndex].sets[setIndex].rightSeconds,
                                     identifier: "right-\(exercise.id)-\(setIndex)", compact: true).frame(maxWidth: .infinity)
                    } else {
                        IntegerField(title: "Durata · s", value: $session.exercises[exerciseIndex].sets[setIndex].durationSeconds,
                                     identifier: "seconds-\(exercise.id)-\(setIndex)", compact: true).frame(maxWidth: .infinity)
                    }
                } else {
                    IntegerField(title: "Reps", value: $session.exercises[exerciseIndex].sets[setIndex].reps,
                                 identifier: "reps-\(exercise.id)-\(setIndex)", compact: true).frame(maxWidth: .infinity)
                }
                Button {
                    toggleSetCompletion(exerciseIndex: exerciseIndex, setIndex: setIndex, exercise: exercise)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(set.done ? Color.white : PivotTheme.muted)
                        .frame(width: 44, height: 48)
                        .background(set.done ? Color.green.opacity(0.75) : PivotTheme.background,
                                    in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain).disabled(!hasStarted || store.locked)
                .accessibilityLabel(set.done ? "Serie \(setIndex + 1) fatta" : "Segna serie \(setIndex + 1) fatta")
                .accessibilityValue(set.done ? "Fatta" : "Da fare")
                .accessibilityIdentifier("set-done-\(exercise.id)-\(setIndex)")
                Button { setOptions = WorkoutSetOptionsTarget(id: set.id) } label: {
                    Image(systemName: "ellipsis").font(.subheadline.bold())
                        .frame(width: 28, height: 48).foregroundStyle(PivotTheme.muted)
                }
                .buttonStyle(.plain).accessibilityLabel("Opzioni serie \(setIndex + 1)")
                .accessibilityIdentifier("set-options-\(exercise.id)-\(setIndex)")
            }
            .padding(.horizontal, 6).padding(.vertical, 4)
            .background(set.done ? Color.green.opacity(0.07) : PivotTheme.raised)
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 22).onEnded { value in
                guard canRemove, abs(value.translation.width) > abs(value.translation.height) else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    revealedSetID = value.translation.width < -35 ? set.id : nil
                }
            })
            // Move the hit region together with the row, leaving Delete tappable.
            .offset(x: isRevealed ? -72 : 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .id(set.id).accessibilityElement(children: .contain)
        .accessibilityIdentifier("set-row-\(exercise.id)-\(setIndex)")
    }
    private func toggleSetCompletion(exerciseIndex: Int, setIndex: Int, exercise: TrainingExercise) {
        let current = session.exercises[exerciseIndex].sets[setIndex]
        let done = !current.done
        if done && !current.canComplete(exercise) {
            message = exercise.usesDuration ? "Inserisci durata e, se selezionata, zavorra prima di segnare Fatta." : "Inserisci carico e Reps prima di segnare Fatta."
            return
        }
        if done {
            session.exercises[exerciseIndex].sets[setIndex].completedAt = Date()
            let seconds = current.restSeconds ?? exercise.restSeconds
            session.rest = seconds > 0 ? .init(exerciseID: exercise.id, setID: current.id, seconds: seconds) : nil
            WorkoutRuntime.focusedSet[session.id] = nil
        } else {
            session.exercises[exerciseIndex].sets[setIndex].completedAt = nil
            if session.rest?.setID == current.id { session.rest = nil }
        }
        revealedSetID = nil
        session.exercises[exerciseIndex].sets[setIndex].done = done
        save()
    }
    private func setLocation(_ id: UUID) -> (exercise: Int, set: Int)? {
        for exerciseIndex in session.exercises.indices {
            if let setIndex = session.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == id }) {
                return (exerciseIndex, setIndex)
            }
        }
        return nil
    }
    private static func markingSetOrigins(_ original: TrainingSession) -> TrainingSession {
        var result = original
        for index in result.exercises.indices {
            result.exercises[index].sets = TrainingSetTemplate.markingOrigins(result.exercises[index].sets,
                                                                            prescribedWorkingSets: result.exercises[index].exercise.sets)
        }
        return result
    }
    private func setOptionsSheet(exerciseIndex: Int, setIndex: Int) -> some View {
        let exercise = session.exercises[exerciseIndex].exercise
        let set = session.exercises[exerciseIndex].sets[setIndex]
        return NavigationStack {
            Form {
                Section("Tipo e intensità") {
                    setTypeMenu(exerciseIndex: exerciseIndex, setIndex: setIndex, expanded: true)
                    Toggle("Failure · cedimento", isOn: Binding(get: {
                        session.exercises[exerciseIndex].sets[setIndex].reachesFailure
                    }, set: { session.exercises[exerciseIndex].sets[setIndex].toFailure = $0 }))
                    if session.exercises[exerciseIndex].sets[setIndex].resolvedKind == .superset {
                        TextField("Gruppo Superset (es. A)", text: supersetBinding(exerciseIndex: exerciseIndex, setIndex: setIndex))
                            .textInputAutocapitalization(.characters)
                    }
                }
                Section("Recupero · \(set.restSeconds ?? exercise.restSeconds) s") {
                    IntegerField(title: "Secondi · 0 = nessuna pausa",
                                 value: $session.exercises[exerciseIndex].sets[setIndex].restSeconds,
                                 identifier: "rest-\(exercise.id)-\(setIndex)")
                    Button("Usa il recupero della scheda") {
                        session.exercises[exerciseIndex].sets[setIndex].restSeconds = nil
                    }
                    Text("Il timer parte quando segni la serie fatta. Questo valore resta salvato per la prossima volta.")
                        .font(.caption).foregroundStyle(PivotTheme.muted)
                }
                Section("Schermata di blocco") {
                    Button("Usa questa serie nei controlli") {
                        guard save() else { return }
                        WorkoutRuntime.focusedSet[session.id] = set.id
                        Task { await WorkoutRuntime.update(session, start: true) }
                        setOptions = nil
                    }
                    .disabled(!hasStarted || session.end != nil || set.done)
                }
                Section {
                    Text(set.isAdditional == true ? "Serie aggiunta: puoi eliminarla con uno swipe a sinistra finché non è fatta." : "Serie prevista dalla scheda: resta obbligatoria e non può essere eliminata.")
                        .font(.caption).foregroundStyle(PivotTheme.muted)
                }
            }
            .navigationTitle("Serie \(setIndex + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { setOptions = nil; save() } } }
            .pivotForm()
        }
        .presentationDetents([.medium, .large])
    }
    private func setTypeMenu(exerciseIndex: Int, setIndex: Int, expanded: Bool = false) -> some View {
        let set = session.exercises[exerciseIndex].sets[setIndex]
        let current = WorkoutSetAppearance(set)
        let workingNumber = session.exercises[exerciseIndex].sets[..<setIndex].filter { $0.resolvedKind == .working }.count + 1
        let badge = current == .working ? String(workingNumber) : current.badge
        return Menu {
            ForEach(WorkoutSetAppearance.allCases.filter { $0 != .failure }) { appearance in
                Button {
                    applySetAppearance(appearance, exerciseIndex: exerciseIndex, setIndex: setIndex)
                } label: {
                    HStack {
                        Text("\(appearance.badge) · \(appearance.name)")
                        if appearance == current { Image(systemName: "checkmark") }
                    }
                }
            }
            Divider()
            Button {
                applySetAppearance(.failure, exerciseIndex: exerciseIndex, setIndex: setIndex)
            } label: {
                if set.reachesFailure { Label("F · Failure", systemImage: "checkmark") }
                else { Text("F · Failure") }
            }
        } label: {
            HStack(spacing: 8) {
                Text(badge)
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(current.color)
                    .frame(width: 40, height: 48)
                    .background(current.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                if expanded {
                    Text(set.resolvedKind.label + (set.reachesFailure ? " · Failure" : ""))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Image(systemName: "chevron.down").font(.caption2.bold()).foregroundStyle(PivotTheme.muted)
                }
            }
        }
        .accessibilityLabel("Serie \(setIndex + 1), \(set.resolvedKind.label)\(set.reachesFailure ? ", Failure" : ""), cambia tipo")
        .accessibilityIdentifier("set-type-\(exerciseIndex)-\(setIndex)")
    }
    private var restCard: some View {
        PivotCard(tint: PivotTheme.blue) {
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                if let rest = session.rest {
                    Text(rest.deadline == nil ? "Recupero in pausa" : rest.remaining(at: context.date) == 0 ? "Recupero terminato" : "Recupero").font(.headline)
                    Text(ActivityTiming.duration(rest.remaining(at: context.date))).font(.title.monospacedDigit())
                }
            }
            HStack {
                Button(session.rest?.deadline == nil ? "Riprendi" : "Pausa") { session.rest?.togglePause(); save() }
                Spacer()
                Button("Reset") {
                    session.rest?.resetCountdown(); save()
                }
            }
            Button("Inizia prossima serie") { WorkoutRuntime.finishRest(&session); save() }.buttonStyle(PivotSecondaryButton())
            Text("La prossima serie chiude il recupero e registra il tempo effettivo. Gli avvisi dipendono dai permessi notifiche e da Full immersion.").font(.caption).foregroundStyle(PivotTheme.muted)
        }
    }
    private func changeExercise(_ exercise: TrainingExercise) {
        do {
            var updated = session
            var library = store.data.training ?? TrainingLibrary()
            updated = TrainingEdits.preservingCatalogChoices(in: updated, library: library)
            if let id = replacementID { try TrainingEdits.replace(in: &updated, exerciseID: id, with: exercise, library: library) }
            else { try TrainingEdits.add(to: &updated, exercise: exercise, library: library) }
            if applyToPlan {
                guard let plan = library.plans.first(where: { $0.id == session.planID }),
                      let day = plan.payload.days.firstIndex(where: { day in session.dayID.map { $0 == day.id } ?? (day.name == session.dayName) }) else { throw TrainingError.invalidPlan }
                var payload = plan.payload
                if let id = replacementID, let index = payload.days[day].exercises.firstIndex(where: { $0.id == id }) { payload.days[day].exercises[index] = exercise }
                else if !payload.days[day].exercises.contains(where: { $0.id == exercise.id }) { payload.days[day].exercises.append(exercise) }
                try TrainingEdits.revise(planID: plan.id, payload: payload, note: "Cambio scelto durante l'allenamento", library: &library)
            }
            updated.updatedAt = Date()
            if let index = library.sessions.firstIndex(where: { $0.id == updated.id }) { library.sessions[index] = updated }
            else { library.sessions.append(updated) }
            try library.validate()
            guard store.change({ $0.training = library }) else { return }; session = updated
            message = applyToPlan ? "Esercizio e scheda aggiornati. Storico conservato." : "Esercizio aggiornato solo in questo allenamento."
        } catch { message = "Cambio non applicato: l'esercizio potrebbe essere già presente o avere serie fatte. Nessun dato precedente è stato eliminato." }
    }
    private func applySetAppearance(_ appearance: WorkoutSetAppearance, exerciseIndex: Int, setIndex: Int) {
        guard session.exercises.indices.contains(exerciseIndex),
              session.exercises[exerciseIndex].sets.indices.contains(setIndex) else { return }
        if appearance == .failure {
            session.exercises[exerciseIndex].sets[setIndex].toFailure = !session.exercises[exerciseIndex].sets[setIndex].reachesFailure
        } else {
            let kind: TrainingSetKind
            switch appearance {
            case .warmup: kind = .warmup
            case .working: kind = .working
            case .backoff: kind = .backoff
            case .superset: kind = .superset
            case .dropSet: kind = .dropSet
            case .failure: return
            }
            session.exercises[exerciseIndex].sets[setIndex].kind = kind
            if kind == .working { session.exercises[exerciseIndex].sets[setIndex].toFailure = false }
            if kind != .superset { session.exercises[exerciseIndex].sets[setIndex].supersetGroup = nil }
            if kind != .warmup { session.exercises[exerciseIndex].sets[setIndex].loadFraction = nil }
            else { TrainingSetTemplate.rememberWarmupFractions(in: &session.exercises[exerciseIndex].sets) }
        }
        save()
    }
    private func supersetBinding(exerciseIndex: Int, setIndex: Int) -> Binding<String> {
        Binding(get: { session.exercises[exerciseIndex].sets[setIndex].supersetGroup ?? "" }, set: {
            session.exercises[exerciseIndex].sets[setIndex].supersetGroup = String($0.prefix(20))
        })
    }
    private func weightBinding(exerciseIndex: Int, setIndex: Int) -> Binding<Double?> {
        Binding(get: { session.exercises[exerciseIndex].sets[setIndex].kg }, set: { value in
            let kind = session.exercises[exerciseIndex].sets[setIndex].resolvedKind
            session.exercises[exerciseIndex].sets[setIndex].kg = value
            if kind == .warmup {
                TrainingSetTemplate.rememberWarmupFractions(in: &session.exercises[exerciseIndex].sets)
            } else if [.working, .superset].contains(kind) {
                let target = TrainingSetTemplate.workingLoad(session.exercises[exerciseIndex].sets)
                let missingFractions = session.exercises[exerciseIndex].sets.contains { $0.resolvedKind == .warmup && $0.kg != nil && $0.loadFraction == nil }
                if missingFractions { TrainingSetTemplate.rememberWarmupFractions(in: &session.exercises[exerciseIndex].sets) }
                TrainingSetTemplate.rescaleWarmups(in: &session.exercises[exerciseIndex].sets, workingLoad: target)
            }
        })
    }
    private func addWarmup(exerciseIndex: Int) {
        var sets = session.exercises[exerciseIndex].sets
        let warmupCount = sets.filter { $0.resolvedKind == .warmup }.count
        let fractions = [0.5, 0.7, 0.85]
        var set = TrainingSet(number: 1, kind: .warmup, loadFraction: fractions[min(warmupCount, fractions.count - 1)], isAdditional: true)
        var candidate = [set]
        TrainingSetTemplate.rescaleWarmups(in: &candidate, workingLoad: TrainingSetTemplate.workingLoad(sets))
        set.kg = candidate[0].kg
        let insertion = sets.firstIndex { $0.resolvedKind != .warmup } ?? sets.endIndex
        sets.insert(set, at: insertion)
        session.exercises[exerciseIndex].sets = TrainingSetTemplate.renumbered(sets)
        save()
    }
    private func addWorkingSet(exerciseIndex: Int) {
        var sets = session.exercises[exerciseIndex].sets
        let previous = sets.last { $0.resolvedKind != .warmup }
        sets.append(TrainingSet(number: sets.count + 1, kg: previous?.kg, reps: previous?.reps, kind: .working,
                                durationSeconds: previous?.durationSeconds, leftSeconds: previous?.leftSeconds,
                                rightSeconds: previous?.rightSeconds, restSeconds: previous?.restSeconds,
                                isAdditional: true))
        session.exercises[exerciseIndex].sets = TrainingSetTemplate.renumbered(sets)
        save()
    }
    private func removeSet(exerciseIndex: Int, setIndex: Int) {
        guard canRemoveSet(exerciseIndex: exerciseIndex, setIndex: setIndex) else { return }
        session.exercises[exerciseIndex].sets.remove(at: setIndex)
        session.exercises[exerciseIndex].sets = TrainingSetTemplate.renumbered(session.exercises[exerciseIndex].sets)
        save()
    }
    private func canRemoveSet(exerciseIndex: Int, setIndex: Int) -> Bool {
        guard session.exercises.indices.contains(exerciseIndex),
              session.exercises[exerciseIndex].sets.indices.contains(setIndex) else { return false }
        let log = session.exercises[exerciseIndex]
        return TrainingSetTemplate.canRemove(log.sets, at: setIndex, prescribedWorkingSets: log.exercise.sets)
    }
    @discardableResult private func save() -> Bool {
        guard !store.locked else { return false }
        if !hasStarted {
            return store.change { data in
                var library = data.training ?? TrainingLibrary()
                for (key, value) in tips { library.tips[key] = value }
                data.training = library
            }
        }
        if let end = session.end, end < session.start { message = "La fine deve essere successiva all'inizio."; return false }
        session.updatedAt = Date()
        let ok = store.saveTraining(session, tips: tips, event: event)
        if ok {
            message = "Allenamento salvato."
            let snapshot = session
            Task { await WorkoutRuntime.scheduleRest(snapshot); await WorkoutRuntime.update(snapshot) }
        }
        return ok
    }
}
