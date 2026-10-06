import SwiftUI
import Charts

actor ExerciseCatalogLoader {
    static let shared = ExerciseCatalogLoader()
    private var cached: [CatalogExercise]?
    func entries() throws -> [CatalogExercise] {
        if let cached { return cached }
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json") else { throw TrainingError.invalidPlan }
        let entries = try ExerciseCatalog.load(from: url); cached = entries; return entries
    }
}

struct ExerciseThumbnail: View {
    let exercise: TrainingExercise
    var body: some View {
        Group {
            if ExerciseCatalog.hasBenchIllustration(exercise) {
                Image("ExerciseBenchPress").resizable().scaledToFit().background(.white)
            } else {
                Image(systemName: "dumbbell.fill").resizable().scaledToFit().padding(22).foregroundStyle(PivotTheme.blue).background(PivotTheme.raised)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 14)).accessibilityHidden(true)
    }
}

struct ExerciseGalleryView: View {
    @EnvironmentObject private var store: PivotStore
    @State private var exercises: [TrainingExercise] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "I tuoi esercizi", detail: "Tocca per i progressi")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 12) {
                ForEach(exercises) { exercise in
                    NavigationLink { ExerciseStatisticsView(exercise: exercise) } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            ExerciseThumbnail(exercise: exercise).frame(height: 110)
                            Text(exercise.name).font(.subheadline.weight(.semibold)).foregroundStyle(PivotTheme.text)
                            Text("Storico e statistiche").font(.caption).foregroundStyle(PivotTheme.muted)
                        }.padding(10).background(PivotTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain).accessibilityIdentifier("exercise-statistics-\(exercise.id)")
                }
            }
        }.task(id: store.data.updatedAt) {
            let library = store.data.training ?? TrainingLibrary()
            let result = await Task.detached(priority: .utility) {
                var byID: [String: TrainingExercise] = [:]
                for session in library.sessions.sorted(by: { $0.start < $1.start }) { for log in session.exercises { byID[log.id] = log.exercise } }
                for plan in library.plans { for day in plan.payload.days { for exercise in day.exercises { byID[exercise.id] = exercise } } }
                return byID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }.value
            guard !Task.isCancelled else { return }; exercises = result
        }
    }
}

struct ExerciseStatisticsView: View {
    @EnvironmentObject private var store: PivotStore
    let exercise: TrainingExercise
    var current: TrainingSession? = nil
    @State private var progress = ExerciseProgress(performances: [])
    @State private var catalogEntry: CatalogExercise?
    var body: some View {
        PivotScreen {
            PivotHeader(title: exercise.name, subtitle: "Solo serie fatte · stesso esercizio e stesso identificativo.")
            ExerciseThumbnail(exercise: exercise).frame(maxWidth: .infinity).frame(height: 210)
            if let entry = catalogEntry {
                PivotCard {
                    Text("Principali: \(entry.muscleSummary)").font(.subheadline.weight(.semibold))
                    if !entry.secondaryMuscles.isEmpty { Text("Secondari: \(entry.secondarySummary)").font(.caption).foregroundStyle(PivotTheme.muted) }
                    Text(entry.equipmentLabel).font(.caption).foregroundStyle(PivotTheme.blue)
                    if let url = entry.photoURL { Link("Apri foto dimostrativa online", destination: url).font(.subheadline) }
                }
            } else if ExerciseCatalog.hasBenchIllustration(exercise) {
                Text("Principali: pettorali · secondari: deltoide anteriore e tricipiti.").font(.caption).foregroundStyle(PivotTheme.muted)
            }
            Text("Le aree rosse indicano i gruppi coinvolti, non misurano la tua attivazione. La tecnica e gli adattamenti si verificano con il coach. Le foto online si aprono solo su tua richiesta.").font(.caption).foregroundStyle(PivotTheme.muted)
            if progress.performances.isEmpty {
                EmptyCard(title: "Il tuo storico parte da qui", message: "Carichi proposti e serie non fatte non entrano nelle statistiche.", icon: "chart.xyaxis.line")
            } else {
                HStack {
                    MetricTile(title: "Miglior carico", value: kg(progress.bestLoad), icon: "dumbbell.fill")
                    MetricTile(title: "Massimale stimato", value: kg(progress.estimatedMax), icon: "chart.line.uptrend.xyaxis", color: PivotTheme.blue)
                }
                HStack {
                    MetricTile(title: "Miglior volume", value: progress.bestVolume.map { "\($0.formatted(.number.precision(.fractionLength(0)))) kg·rep" } ?? "—", icon: "sum")
                    MetricTile(title: "Allenamenti", value: "\(progress.performances.count)", icon: "calendar")
                }
                PivotCard {
                    Text("Progressione del carico").font(.headline)
                    Chart(Array(progress.performances.suffix(30))) { point in
                        LineMark(x: .value("Data", point.date), y: .value("Carico kg", point.bestLoad)).foregroundStyle(PivotTheme.accent)
                        PointMark(x: .value("Data", point.date), y: .value("Carico kg", point.bestLoad)).foregroundStyle(PivotTheme.accent)
                    }.frame(height: 180)
                    Text("Migliore serie di ogni allenamento · fino agli ultimi 30").font(.caption).foregroundStyle(PivotTheme.muted)
                }
                Text("Stima Epley: kg × (1 + ripetizioni/30), solo serie da 1 a 10 ripetizioni; a 1 ripetizione mostro il carico fatto. È un riferimento teorico, soprattutto se non eri vicino al cedimento: non è un carico da provare. Volume = somma di kg × ripetizioni, secondo il carico che inserisci (per manubri usa sempre la stessa convenzione).").font(.caption).foregroundStyle(PivotTheme.muted)
                SectionHeading(title: "Cronologia recente")
                ForEach(Array(progress.performances.reversed().prefix(12))) { point in
                    PivotCard {
                        Text(DisplayDate.label(point.date, format: "d MMM yyyy") + (point.finished ? "" : " · in corso")).font(.headline)
                        Text(point.sets.map { "\(($0.kg ?? 0).formatted()) kg × \($0.reps ?? 0)" }.joined(separator: " · ")).font(.subheadline)
                        Text("Volume \(point.volume.formatted()) kg·rep · stima \(kg(point.estimatedMax))").font(.caption).foregroundStyle(PivotTheme.blue)
                    }
                }
            }
        }.navigationTitle("Progressi")
            .task(id: "\(exercise.id)|\(store.data.updatedAt.timeIntervalSince1970)|\(current?.updatedAt.timeIntervalSince1970 ?? 0)") {
                let library = store.data.training ?? TrainingLibrary(), current = current, id = exercise.id
                let result = await Task.detached(priority: .utility) { ExerciseProgress.calculate(exerciseID: id, library: library, current: current) }.value
                guard !Task.isCancelled else { return }; progress = result
                if let entries = try? await ExerciseCatalogLoader.shared.entries() { catalogEntry = ExerciseCatalog.match(exercise, in: entries) }
            }
    }
    private func kg(_ value: Double?) -> String { value.map { "\($0.formatted(.number.precision(.fractionLength(1)))) kg" } ?? "—" }
}

struct ExercisePickerView: View {
    @EnvironmentObject private var store: PivotStore
    @Environment(\.dismiss) private var dismiss
    let onSelect: (TrainingExercise) -> Void
    @State private var entries: [CatalogExercise] = []
    @State private var known: [TrainingExercise] = []
    @State private var query = ""
    @State private var muscle = ""
    @State private var equipment = ""
    @State private var customName = ""
    @State private var error: String?
    private var filtered: [CatalogExercise] {
        let search = EventCoalescer.normalized(query)
        return entries.filter {
            (muscle.isEmpty || $0.primaryMuscles.contains(muscle)) && (equipment.isEmpty || $0.equipment == equipment)
            && (search.isEmpty || EventCoalescer.normalized($0.name + " " + $0.displayName + " " + $0.muscleSummary + " " + $0.equipmentLabel).contains(search))
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section("Filtra il catalogo offline") {
                    Picker("Muscoli principali", selection: $muscle) {
                        Text("Tutti").tag("")
                        ForEach(ExerciseCatalog.muscleNames.keys.sorted(), id: \.self) { Text(ExerciseCatalog.muscleNames[$0] ?? $0).tag($0) }
                    }
                    Picker("Attrezzo", selection: $equipment) {
                        Text("Tutti").tag("")
                        ForEach(ExerciseCatalog.equipmentNames.keys.sorted(), id: \.self) { Text(ExerciseCatalog.equipmentNames[$0] ?? $0).tag($0) }
                    }
                }
                if !known.isEmpty {
                    Section("Già nelle tue schede / nello storico") {
                        ForEach(known.filter { query.isEmpty || EventCoalescer.normalized($0.name).contains(EventCoalescer.normalized(query)) }) { exercise in
                            NavigationLink(exercise.name) { setup(exercise) }
                        }
                    }
                }
                Section("Catalogo · \(filtered.count) risultati") {
                    ForEach(Array(filtered.prefix(100))) { entry in
                        NavigationLink { setup(entry.prescription()) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.displayName)
                                if entry.displayName != entry.name { Text(entry.name).font(.caption).foregroundStyle(PivotTheme.muted) }
                                Text(entry.muscleSummary + " · " + entry.equipmentLabel).font(.caption).foregroundStyle(PivotTheme.blue)
                            }
                        }
                    }
                    if filtered.count > 100 { Text("Affina la ricerca o i filtri per vedere gli altri risultati.").font(.caption) }
                }
                Section("Non trovi la tua variante?") {
                    TextField("Nome esatto dell'esercizio", text: $customName).accessibilityIdentifier("custom-exercise-name")
                    NavigationLink("Crea esercizio personale") {
                        setup(TrainingExercise(id: "custom:\(UUID().uuidString)", name: customName.trimmingCharacters(in: .whitespacesAndNewlines), sets: 1, reps: "Da concordare", restSeconds: 0, coachNotes: ""))
                    }.disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let error { Text(error).foregroundStyle(PivotTheme.amber) }
                Section {
                    Text("Il catalogo non è una scheda prescritta. Scegli serie, ripetizioni e recupero concordati con il coach. Molti nomi restano in inglese; i più comuni hanno un nome italiano. Fonte: free-exercise-db (Unlicense), copia offline di \(entries.count) esercizi. Non contiene ogni variante possibile.").font(.caption)
                    Link("Fonte e licenza", destination: URL(string: "https://github.com/yuhonas/free-exercise-db")!)
                }
            }.pivotForm().navigationTitle("Scegli esercizio").searchable(text: $query, prompt: "Nome, muscolo o attrezzo")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } } }
                .task {
                    do { entries = try await ExerciseCatalogLoader.shared.entries() } catch { self.error = "Catalogo non disponibile. Puoi comunque aggiungere un esercizio personale." }
                    let library = store.data.training ?? TrainingLibrary()
                    var byID: [String: TrainingExercise] = [:]
                    for session in library.sessions { for log in session.exercises { byID[log.id] = log.exercise } }
                    for plan in library.plans { for day in plan.payload.days { for exercise in day.exercises { byID[exercise.id] = exercise } } }
                    known = byID.values.sorted { $0.name < $1.name }
                }
        }
    }
    private func setup(_ exercise: TrainingExercise) -> some View {
        ExerciseSetupView(exercise: exercise) { selected in onSelect(selected); dismiss() }
    }
}

struct ExerciseSetupView: View {
    @State var exercise: TrainingExercise
    let onSelect: (TrainingExercise) -> Void
    var body: some View {
        PivotScreen {
            ExerciseStatisticsViewLink(exercise: exercise)
            PivotCard {
                Text(exercise.name).font(.headline)
                Stepper("Serie: \(exercise.sets)", value: $exercise.sets, in: 1...30)
                TextField("Ripetizioni / indicazioni del coach", text: Binding(get: { exercise.reps == "Da concordare" ? "" : exercise.reps }, set: { exercise.reps = $0 })).accessibilityIdentifier("exercise-repetitions")
                Stepper("Recupero: \(exercise.restSeconds) sec", value: $exercise.restSeconds, in: 0...3600, step: 15)
                Text("0 secondi = recupero non indicato; non è un consiglio di allenarti senza pausa.").font(.caption).foregroundStyle(PivotTheme.muted)
                TextField("Note del coach", text: $exercise.coachNotes, axis: .vertical)
            }
            Button("Usa questo esercizio") { onSelect(exercise) }.buttonStyle(PivotPrimaryButton())
                .disabled(exercise.reps.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || exercise.reps == "Da concordare")
        }.navigationTitle("Imposta esercizio")
    }
}

struct ExerciseStatisticsViewLink: View {
    let exercise: TrainingExercise
    var body: some View {
        NavigationLink { ExerciseStatisticsView(exercise: exercise) } label: {
            HStack {
                ExerciseThumbnail(exercise: exercise).frame(width: 80, height: 80)
                Text("Illustrazione, muscoli e statistiche").font(.subheadline)
                Image(systemName: "chevron.right")
            }
        }.buttonStyle(.plain)
    }
}
