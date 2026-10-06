import SwiftUI
import UniformTypeIdentifiers
import UIKit

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
                ForEach(plan.payload.days) { day in
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
                SectionHeading(title: "Ultimi allenamenti")
                ForEach(library.sessions.sorted { $0.start > $1.start }.prefix(20)) { session in
                    NavigationLink {
                        TrainingSessionView(session: session, tips: library.tips, event: nil)
                    } label: {
                        PivotCard { ActionRow(title: session.dayName, subtitle: "\(PivotDate.shortDate(session.start)) · \(session.end == nil ? "in corso" : "terminato")", icon: "clock.arrow.circlepath") }
                    }.buttonStyle(.plain)
                }
            }
            if let message { Text(message).font(.subheadline).foregroundStyle(PivotTheme.amber) }
        }.navigationTitle("Palestra")
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
                        ForEach(plan.payload.days) { day in
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
            let payload = TrainingPlanPayload(formatVersion: 1, name: "Scheda TEST", days: [TrainingDay(id: "test-a", name: "Giorno test", exercises: [TrainingExercise(id: "test-exercise", name: "Esercizio test", sets: 1, reps: "8", restSeconds: 60, coachNotes: "Nota test")])])
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
    let event: CalendarItem?
    init(plan: TrainingPlan, day: TrainingDay, library: TrainingLibrary, event: CalendarItem?) {
        self.event = event
        let existing = library.sessions.first { $0.calendarEventID == event?.id && event != nil && $0.planID == plan.id }
            ?? library.sessions.filter { $0.end == nil && $0.planID == plan.id && $0.dayName == day.name && $0.calendarEventID == nil && event == nil }.sorted { $0.start > $1.start }.first
        _session = State(initialValue: existing ?? library.makeSession(plan: plan, day: day, eventID: event?.id))
        _tips = State(initialValue: library.tips)
        _hasStarted = State(initialValue: existing != nil)
    }
    init(session: TrainingSession, tips: [String: String], event: CalendarItem?) {
        _session = State(initialValue: session); _tips = State(initialValue: tips); self.event = event
        _hasStarted = State(initialValue: true)
    }
    var body: some View {
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
                    Button("Termina allenamento") { session.end = Date(); save() }.buttonStyle(PivotPrimaryButton())
                }
            }
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
            .sheet(isPresented: $sharing) { if let export { ShareSheet(items: [export]) } }
    }
    private func exerciseCard(_ index: Int) -> some View {
        let exercise = session.exercises[index].exercise
        let previous = (store.data.training ?? TrainingLibrary()).previous(exerciseID: exercise.id, before: session.start, excluding: session.id)
        return PivotCard {
            NavigationLink { ExerciseStatisticsView(exercise: exercise, current: hasStarted ? session : nil) } label: {
                HStack {
                    ExerciseThumbnail(exercise: exercise).frame(width: 74, height: 74)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(index + 1). \(exercise.name)").font(.headline)
                        Text("Apri cronologia e progressi").font(.caption).foregroundStyle(PivotTheme.blue)
                    }
                    Spacer(); Image(systemName: "chevron.right")
                }
            }.buttonStyle(.plain).accessibilityIdentifier("workout-exercise-statistics-\(exercise.id)")
            Button("Cambia esercizio") { replacementID = exercise.id; selectingExercise = true }
                .disabled(!hasStarted || session.exercises[index].sets.contains(where: \.done) || store.locked)
            if session.exercises[index].sets.contains(where: \.done) { Text("Hai già registrato delle serie: per conservare ciò che hai fatto, aggiungi il nuovo esercizio come extra.").font(.caption).foregroundStyle(PivotTheme.muted) }
            Text("\(exercise.sets) serie × \(exercise.reps) · recupero \(ActivityTiming.duration(exercise.restSeconds))").font(.subheadline).foregroundStyle(PivotTheme.accent)
            if !exercise.coachNotes.isEmpty { Text(exercise.coachNotes).font(.caption).foregroundStyle(PivotTheme.muted) }
            if let previous {
                Text("Ultima volta: " + previous.sets.filter(\.done).map { "\($0.kg ?? 0) kg × \($0.reps ?? 0)" }.joined(separator: " · ")).font(.caption).foregroundStyle(PivotTheme.blue)
            } else { Text("Prima registrazione: nessun carico preimpostato.").font(.caption).foregroundStyle(PivotTheme.muted) }
            ForEach(session.exercises[index].sets.indices, id: \.self) { setIndex in
                VStack(spacing: 8) {
                    HStack {
                        Text("Serie \(setIndex + 1)").font(.subheadline.weight(.semibold))
                        Spacer()
                        Toggle("Fatta", isOn: Binding(get: { session.exercises[index].sets[setIndex].done }, set: { done in
                            let set = session.exercises[index].sets[setIndex]
                            if done && (set.kg == nil || set.reps == nil) { message = "Inserisci carico e ripetizioni prima di segnare la serie fatta."; return }
                            session.exercises[index].sets[setIndex].done = done; save()
                        })).fixedSize().disabled(!hasStarted).accessibilityIdentifier("set-done-\(exercise.id)-\(setIndex)")
                    }
                    HStack(spacing: 18) {
                        DecimalField(title: "Carico", unit: "kg", value: $session.exercises[index].sets[setIndex].kg, identifier: "weight-\(exercise.id)-\(setIndex)")
                        IntegerField(title: "Ripetizioni", value: $session.exercises[index].sets[setIndex].reps, identifier: "reps-\(exercise.id)-\(setIndex)")
                    }
                    Divider()
                }
            }
            TextField("Note di questa sessione…", text: $session.exercises[index].notes, axis: .vertical).lineLimit(2...5)
            Label("Promemoria tecnici · restano salvati", systemImage: "pin.fill").font(.subheadline.weight(.semibold))
            TextField("Panca livello 5, posizione, gomiti…", text: Binding(get: { tips[exercise.id] ?? "" }, set: { tips[exercise.id] = $0 }), axis: .vertical).lineLimit(3...8)
                .padding(12).background(PivotTheme.raised, in: RoundedRectangle(cornerRadius: 12))
        }
    }
    private func changeExercise(_ exercise: TrainingExercise) {
        do {
            var updated = session
            var library = store.data.training ?? TrainingLibrary()
            if let id = replacementID { try TrainingEdits.replace(in: &updated, exerciseID: id, with: exercise, library: library) }
            else { try TrainingEdits.add(to: &updated, exercise: exercise, library: library) }
            if applyToPlan {
                guard let plan = library.plans.first(where: { $0.id == session.planID }),
                      let day = plan.payload.days.firstIndex(where: { $0.name == session.dayName }) else { throw TrainingError.invalidPlan }
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
        if ok { message = "Allenamento salvato." }
        return ok
    }
}
