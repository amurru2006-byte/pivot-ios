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

enum ExerciseMuscleGroup: String, CaseIterable, Identifiable {
    case all, chest, back, shoulders, arms, legs, core, unresolved
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: "Tutti"; case .chest: "Petto"; case .back: "Schiena"; case .shoulders: "Spalle"
        case .arms: "Braccia"; case .legs: "Gambe"; case .core: "Core"; case .unresolved: "Da associare"
        }
    }
    func matches(_ entry: CatalogExercise?) -> Bool {
        guard self != .all else { return true }
        guard let entry else { return self == .unresolved }
        let muscles = Set(entry.primaryMuscles)
        switch self {
        case .chest: return muscles.contains("chest")
        case .back: return !muscles.isDisjoint(with: ["lats", "middle back", "lower back", "traps"])
        case .shoulders: return muscles.contains("shoulders")
        case .arms: return !muscles.isDisjoint(with: ["biceps", "triceps", "forearms"])
        case .legs: return !muscles.isDisjoint(with: ["quadriceps", "hamstrings", "glutes", "calves", "adductors", "abductors"])
        case .core: return muscles.contains("abdominals")
        case .unresolved: return false
        case .all: return true
        }
    }
}

struct ExerciseGroupBar: View {
    @Binding var selection: ExerciseMuscleGroup
    var includeUnresolved = true
    var identifier = "exercise-group-bar"
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ExerciseMuscleGroup.allCases.filter { includeUnresolved || $0 != .unresolved }) { group in
                    Button(group.label) { selection = group }
                        .font(.caption.weight(.semibold)).padding(.horizontal, 13).padding(.vertical, 8)
                        .foregroundStyle(selection == group ? Color.black : PivotTheme.text)
                        .background(selection == group ? PivotTheme.accent : PivotTheme.raised, in: Capsule())
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(identifier + "-" + group.rawValue)
                }
            }
        }.accessibilityLabel("Filtra per gruppo muscolare principale").accessibilityIdentifier(identifier)
    }
}

struct ExerciseThumbnail: View {
    @EnvironmentObject private var store: PivotStore
    let exercise: TrainingExercise
    private var displayedExercise: TrainingExercise { TrainingEdits.withSavedCatalog(exercise, library: store.data.training ?? TrainingLibrary()) }
    @State private var photoURL: URL?
    @State private var lookupFinished = false
    var body: some View {
        thumbnailContent.clipShape(RoundedRectangle(cornerRadius: 14)).accessibilityHidden(true)
            .task(id: thumbnailIdentity) { await loadThumbnail() }
    }
    private var thumbnailIdentity: String {
        [exercise.id, exercise.name, displayedExercise.catalogID ?? ""].joined(separator: "|")
    }
    @ViewBuilder private var thumbnailContent: some View {
        if ExerciseCatalog.hasBenchIllustration(displayedExercise) {
            Image("ExerciseBenchPress").resizable().scaledToFit().background(.white)
        } else if let photoURL {
            AsyncImage(url: photoURL, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                remoteThumbnail(phase)
            }.background(.white)
        } else {
            fallback
        }
    }
    @ViewBuilder private func remoteThumbnail(_ phase: AsyncImagePhase) -> some View {
        switch phase {
        case .success(let image): image.resizable().scaledToFit()
        case .failure: fallback
        default: ProgressView().tint(PivotTheme.blue)
        }
    }
    private func loadThumbnail() async {
        let resolved = displayedExercise
        guard !ExerciseCatalog.hasBenchIllustration(resolved) else { lookupFinished = true; return }
        if let entries = try? await ExerciseCatalogLoader.shared.entries() {
            guard !Task.isCancelled else { return }
            photoURL = ExerciseCatalog.match(resolved, in: entries)?.photoURL
        }
        lookupFinished = true
    }
    private var fallback: some View {
        ZStack {
            PivotTheme.raised
            Image(systemName: lookupFinished ? "figure.strengthtraining.traditional" : "photo")
                .resizable().scaledToFit().padding(24).foregroundStyle(PivotTheme.blue)
        }
    }
}

struct ExerciseGalleryView: View {
    @EnvironmentObject private var store: PivotStore
    @State private var exercises: [TrainingExercise] = []
    @State private var catalogByExerciseID: [String: CatalogExercise] = [:]
    @State private var catalogReady = false
    @State private var group: ExerciseMuscleGroup = .all
    private var visibleExercises: [TrainingExercise] { exercises.filter { group.matches(catalogByExerciseID[$0.id]) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "I tuoi esercizi", detail: "Tocca per i progressi")
            ExerciseGroupBar(selection: $group)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 12) {
                ForEach(visibleExercises) { exercise in
                    VStack(alignment: .leading, spacing: 9) {
                        NavigationLink { ExerciseStatisticsView(exercise: exercise) } label: {
                            VStack(alignment: .leading, spacing: 9) {
                            ExerciseThumbnail(exercise: exercise).frame(height: 110)
                            Text(exercise.name).font(.subheadline.weight(.semibold)).foregroundStyle(PivotTheme.text)
                            Text("Storico e statistiche").font(.caption).foregroundStyle(PivotTheme.muted)
                            }
                        }.buttonStyle(.plain).accessibilityIdentifier("exercise-statistics-\(exercise.id)")
                        if catalogReady && catalogByExerciseID[exercise.id] == nil { ExerciseImageAssignmentButton(exercise: exercise) }
                    }.padding(10).background(PivotTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }.task(id: store.data.updatedAt) {
            let library = store.data.training ?? TrainingLibrary()
            let entries = (try? await ExerciseCatalogLoader.shared.entries()) ?? []
            let result = await Task.detached(priority: .utility) {
                var result: [TrainingExercise] = [], seen = Set<String>()
                let active = library.activePlan.map { [$0] } ?? []
                let plans = active + library.plans.filter { $0.id != library.activePlanID }
                for plan in plans {
                    for day in TrainingDayOrder.corrected(plan.payload.days) {
                        for exercise in day.exercises where seen.insert(exercise.id).inserted { result.append(exercise) }
                    }
                }
                var historyOnly: [TrainingExercise] = []
                for session in library.sessions.sorted(by: { $0.start < $1.start }) {
                    for log in session.exercises where seen.insert(log.id).inserted { historyOnly.append(log.exercise) }
                }
                let ordered = result + historyOnly.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                return (ordered, Dictionary(uniqueKeysWithValues: ordered.compactMap { exercise in
                    ExerciseCatalog.match(exercise, in: entries).map { (exercise.id, $0) }
                }))
            }.value
            guard !Task.isCancelled else { return }
            exercises = result.0; catalogByExerciseID = result.1; catalogReady = true
        }
    }
}

struct ExerciseImageAssignmentButton: View {
    @EnvironmentObject private var store: PivotStore
    let exercise: TrainingExercise
    @State private var choosing = false
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button("Scegli tu l'immagine") { choosing = true }
                .font(.caption.weight(.bold)).foregroundStyle(.red)
                .accessibilityIdentifier("choose-exercise-image-\(exercise.id)")
            if let message { Text(message).font(.caption2).foregroundStyle(PivotTheme.amber) }
        }.sheet(isPresented: $choosing) {
            ExerciseImagePickerView(exercise: exercise) { entry in
                do {
                    var library = store.data.training ?? TrainingLibrary()
                    try TrainingEdits.associateCatalog(exerciseID: exercise.id, catalogID: entry.id, library: &library)
                    if store.change({ $0.training = library }) { message = "Immagine associata." }
                } catch { message = "Non sono riuscito ad associare l'immagine." }
                choosing = false
            }
        }
    }
}

struct ExerciseImagePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let exercise: TrainingExercise
    let onSelect: (CatalogExercise) -> Void
    @State private var entries: [CatalogExercise] = []
    @State private var query = ""
    @State private var group: ExerciseMuscleGroup = .all
    @State private var showAll = false
    @State private var visibleLimit = 100
    @State private var error: String?
    private var suggestions: [CatalogExercise] { ExerciseCatalog.suggestions(for: exercise, in: entries) }
    private var filtered: [CatalogExercise] {
        let search = EventCoalescer.normalized(query)
        return entries.filter { entry in
            group.matches(entry) && (search.isEmpty || EventCoalescer.normalized(entry.name + " " + entry.displayName + " " + entry.muscleSummary + " " + entry.equipmentLabel).contains(search))
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Scegli soltanto la variante che corrisponde davvero all'esercizio. Cambia l'immagine e i muscoli mostrati, non il nome, la scheda o lo storico.").font(.caption)
                } header: { Text(exercise.name) }
                if !suggestions.isEmpty {
                    Section("Varianti suggerite") {
                        ForEach(suggestions) { entry in catalogRow(entry) }
                    }
                }
                if !showAll {
                    Section {
                        Button("Non c'è? Cerca in tutto il catalogo") { showAll = true }
                    }
                } else {
                    Section("Gruppo muscolare principale") { ExerciseGroupBar(selection: $group, includeUnresolved: false, identifier: "image-picker-group-bar") }
                    Section("Catalogo completo · \(filtered.count) risultati") {
                        ForEach(Array(filtered.prefix(visibleLimit))) { entry in catalogRow(entry) }
                        if filtered.count > visibleLimit { Button("Mostra altri esercizi") { visibleLimit += 100 } }
                    }
                }
                if let error { Text(error).foregroundStyle(PivotTheme.amber) }
            }.navigationTitle("Scegli immagine")
                .searchable(text: $query, prompt: "Nome, muscolo o attrezzo")
                .onChange(of: query) { _, value in if !value.isEmpty { showAll = true } }
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } } }
                .task {
                    do { entries = try await ExerciseCatalogLoader.shared.entries() }
                    catch { self.error = "Catalogo non disponibile." }
                }
        }
    }
    private func catalogRow(_ entry: CatalogExercise) -> some View {
        Button { onSelect(entry) } label: {
            HStack(spacing: 12) {
                AsyncImage(url: entry.photoURL) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFit() }
                    else { Image(systemName: "photo").foregroundStyle(PivotTheme.blue) }
                }.frame(width: 68, height: 68).background(.white, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.displayName).foregroundStyle(PivotTheme.text)
                    if entry.displayName != entry.name { Text(entry.name).font(.caption2).foregroundStyle(PivotTheme.muted) }
                    Text("Principale: \(entry.muscleSummary) · \(entry.equipmentLabel)").font(.caption).foregroundStyle(PivotTheme.blue)
                }
            }
        }.buttonStyle(.plain).accessibilityIdentifier("catalog-image-\(entry.id)")
    }
}

struct ExerciseStatisticsView: View {
    @EnvironmentObject private var store: PivotStore
    let exercise: TrainingExercise
    var current: TrainingSession? = nil
    @State private var progress = ExerciseProgress(performances: [])
    @State private var catalogEntry: CatalogExercise?
    @State private var catalogReady = false
    private var displayedExercise: TrainingExercise { TrainingEdits.withSavedCatalog(exercise, library: store.data.training ?? TrainingLibrary()) }
    var body: some View {
        PivotScreen {
            PivotHeader(title: exercise.name, subtitle: "Solo serie fatte · stesso esercizio e stesso identificativo.")
            ExerciseThumbnail(exercise: exercise).frame(maxWidth: .infinity).frame(height: 210)
            if catalogReady && catalogEntry == nil { ExerciseImageAssignmentButton(exercise: exercise) }
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
            Text("Le aree rosse indicano i gruppi coinvolti, non misurano la tua attivazione. La tecnica e gli adattamenti si verificano con il coach. Le miniature visibili vengono caricate da GitHub senza inviare il tuo storico.").font(.caption).foregroundStyle(PivotTheme.muted)
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
                if let entries = try? await ExerciseCatalogLoader.shared.entries() { catalogEntry = ExerciseCatalog.match(displayedExercise, in: entries) }
                catalogReady = true
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
    @State private var group: ExerciseMuscleGroup = .all
    @State private var equipment = ""
    @State private var customName = ""
    @State private var error: String?
    private var filtered: [CatalogExercise] {
        let search = EventCoalescer.normalized(query)
        return entries.filter {
            group.matches($0) && (equipment.isEmpty || $0.equipment == equipment)
            && (search.isEmpty || EventCoalescer.normalized($0.name + " " + $0.displayName + " " + $0.muscleSummary + " " + $0.equipmentLabel).contains(search))
        }
    }
    private var filteredKnown: [TrainingExercise] {
        let search = EventCoalescer.normalized(query)
        return known.filter { exercise in
            let entry = ExerciseCatalog.match(exercise, in: entries)
            return group.matches(entry) && (equipment.isEmpty || entry?.equipment == equipment)
                && (search.isEmpty || EventCoalescer.normalized(exercise.name + " " + (entry?.muscleSummary ?? "") + " " + (entry?.equipmentLabel ?? "")).contains(search))
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section("Filtra il catalogo offline") {
                    Text("Gruppo muscolare principale").font(.caption.weight(.semibold))
                    ExerciseGroupBar(selection: $group, includeUnresolved: false, identifier: "exercise-picker-group-bar")
                    Picker("Attrezzo", selection: $equipment) {
                        Text("Tutti").tag("")
                        ForEach(ExerciseCatalog.equipmentNames.keys.sorted(), id: \.self) { Text(ExerciseCatalog.equipmentNames[$0] ?? $0).tag($0) }
                    }
                }
                if !filteredKnown.isEmpty {
                    Section("Già nelle tue schede / nello storico") {
                        ForEach(filteredKnown) { exercise in
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
