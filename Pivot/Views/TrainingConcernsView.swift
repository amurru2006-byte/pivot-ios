import SwiftUI

struct TrainingConcernEditorTarget: Identifiable {
    var id: UUID { draft.id }
    var draft: TrainingConcern
    var original: TrainingConcern?
    init(_ original: TrainingConcern) { self.original = original; draft = original }
    init(kind: TrainingConcernKind, exercise: TrainingExercise? = nil, sessionID: UUID? = nil) {
        original = nil
        draft = TrainingConcern(kind: kind, exercises: exercise.map { [TrainingConcernExercise($0)] } ?? [], originatingSessionID: sessionID)
    }
}

struct TrainingConcernsView: View {
    @EnvironmentObject var store: PivotStore
    @State private var editing: TrainingConcernEditorTarget?
    private var all: [TrainingConcern] { TrainingConcerns.sorted(store.data.training?.concerns ?? []) }
    var body: some View {
        PivotScreen {
            PivotHeader(title: "Dolori e infortuni", subtitle: "Le tue segnalazioni, non diagnosi di Pivot.")
            Text("Collega una segnalazione ai movimenti interessati: l’avviso comparirà anche negli allenamenti successivi. Non cambia da solo carichi o scheda e non autorizza un aumento.")
                .font(.subheadline).foregroundStyle(PivotTheme.muted)
            Button("Nuova segnalazione") { editing = .init(kind: .pain) }
                .buttonStyle(PivotPrimaryButton()).disabled(store.locked || store.isRestoring)
                .accessibilityIdentifier("new-training-concern")
            if all.isEmpty {
                EmptyCard(title: "Nessuna segnalazione", message: "Puoi aggiungerne una qui o dal menu ⋯ dell’esercizio.", icon: "heart.text.square")
                    .accessibilityIdentifier("training-concerns-empty")
            }
            ForEach([true, false], id: \.self) { active in
                let values = all.filter { $0.isActive == active }
                if !values.isEmpty {
                    SectionHeading(title: active ? "Da tenere presenti" : "Non più presenti · storico")
                    ForEach(values) { concern in
                        PivotCard {
                            Text(concern.location).font(.headline)
                            Text("\(concern.kind.label) · \(PivotDate.shortDate(concern.observedAt))")
                                .font(.subheadline).foregroundStyle(PivotTheme.muted)
                            Text(concern.exercises.isEmpty ? "Nessun esercizio collegato" : concern.exercises.map(\.name).joined(separator: " · "))
                                .font(.caption).foregroundStyle(PivotTheme.muted)
                            if !concern.notes.isEmpty { Text(concern.notes).font(.caption).lineLimit(3) }
                            Button(active ? "Apri e aggiorna" : "Apri · puoi riattivarla") { editing = .init(concern) }
                                .buttonStyle(PivotSecondaryButton()).disabled(store.locked || store.isRestoring)
                                .accessibilityLabel("Apri segnalazione \(concern.location) del \(PivotDate.shortDate(concern.observedAt))")
                                .accessibilityIdentifier("concern-open-\(concern.id.uuidString)")
                        }.accessibilityElement(children: .contain)
                    }
                }
            }
        }.navigationTitle("Dolori e infortuni")
            .sheet(item: $editing) { TrainingConcernEditor(target: $0) }
    }
}

struct TrainingConcernEditor: View {
    private enum Field: Hashable { case area, notes, guidance, source }
    @EnvironmentObject var store: PivotStore
    @Environment(\.dismiss) private var dismiss
    @State private var concern: TrainingConcern
    @State private var expected: TrainingConcern?
    @State private var busy = false
    @State private var message: String?
    @FocusState private var focusedField: Field?
    let additionalExercises: [TrainingExercise]
    init(target: TrainingConcernEditorTarget, additionalExercises: [TrainingExercise] = []) {
        _concern = State(initialValue: target.draft)
        _expected = State(initialValue: target.original)
        self.additionalExercises = additionalExercises
    }
    private var candidates: [TrainingConcernExercise] {
        let available = additionalExercises + (store.data.training?.plans ?? []).flatMap { $0.payload.days }.flatMap { $0.exercises }
        var seen = Set<String>()
        // Retain linked snapshots even after a plan is revised or removed.
        return (concern.exercises + available.map(TrainingConcernExercise.init)).filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("È una tua segnalazione, non una diagnosi. Pivot non deduce la causa dai carichi e non prescrive un percorso di recupero.")
                        .font(.subheadline).foregroundStyle(PivotTheme.muted)
                    Picker("Tipo", selection: $concern.kind) {
                        ForEach(TrainingConcernKind.allCases) { Text($0.label).tag($0) }
                    }
                    TextField("Zona (es. ginocchio)", text: $concern.area)
                        .focused($focusedField, equals: .area)
                        .submitLabel(.done).onSubmit { focusedField = nil }
                        .accessibilityIdentifier("concern-area")
                    Picker("Lato", selection: $concern.side) {
                        ForEach(TrainingConcernSide.allCases) { Text($0.label).tag($0) }
                    }
                    DatePicker("Avvertito dal", selection: $concern.observedAt, in: ...Date(), displayedComponents: [.date])
                    Toggle("Indica intensità da 0 a 10", isOn: Binding(get: { concern.intensity != nil }, set: { concern.intensity = $0 ? 5 : nil }))
                    if concern.intensity != nil {
                        Stepper("Intensità riferita: \(concern.intensity ?? 0) / 10", value: Binding(get: { concern.intensity ?? 0 }, set: { concern.intensity = $0 }), in: 0...10)
                    }
                    TextField("Quando lo senti e cosa cambia…", text: $concern.notes, axis: .vertical).lineLimit(2...6)
                        .focused($focusedField, equals: .notes)
                        .accessibilityIdentifier("concern-notes")
                } header: { Text("Cosa hai avvertito") }
                Section {
                    DisclosureGroup("Esercizi collegati") {
                        ForEach(candidates) { exercise in
                            Toggle(exercise.name, isOn: Binding(get: { concern.exercises.contains { $0.id == exercise.id } }, set: { selected in
                                if selected { concern.exercises.append(exercise) }
                                else { concern.exercises.removeAll { $0.id == exercise.id } }
                            })).accessibilityIdentifier("concern-link-\(exercise.id)")
                        }
                    }
                    Text("Gli avvisi valgono solo per i movimenti che selezioni, incluse le varianti identiche del catalogo. Non collego esercizi automaticamente in base alla zona. Senza collegamenti, la segnalazione resta in questa sezione.")
                        .font(.caption).foregroundStyle(PivotTheme.muted)
                } header: { Text("Più movimenti, una segnalazione") }
                Section {
                    TextField("Indicazioni ricevute (facoltative)", text: $concern.professionalGuidance, axis: .vertical).lineLimit(2...6)
                        .focused($focusedField, equals: .guidance)
                    TextField("Da chi e quando (facoltativo)", text: $concern.guidanceSource)
                        .focused($focusedField, equals: .source)
                        .submitLabel(.done).onSubmit { focusedField = nil }
                    Text("Sono informazioni riportate da te. Pivot non le inventa e non le trasforma in aumenti automatici o criteri di idoneità.")
                        .font(.caption).foregroundStyle(PivotTheme.muted)
                } header: { Text("Indicazioni del professionista") }
                Section {
                    Toggle("Non più presente", isOn: Binding(get: { !concern.isActive }, set: { concern.resolvedAt = $0 ? max(Date(), concern.observedAt) : nil }))
                        .accessibilityIdentifier("concern-resolved")
                    Text("Resta nello storico e puoi riattivarla. Segnarla non più presente rimuove gli avvisi, ma non equivale a un’autorizzazione medica al rientro.")
                        .font(.caption).foregroundStyle(PivotTheme.muted)
                    Text("Resta nel backup personale di Pivot. Non viene aggiunta ai PDF per il personal o inviata automaticamente al Coach.")
                        .font(.caption).foregroundStyle(PivotTheme.muted)
                    if let message { Text(message).foregroundStyle(PivotTheme.amber).accessibilityIdentifier("concern-save-message") }
                    if busy { ProgressView("Salvo la segnalazione…") }
                }
            }.scrollDismissesKeyboard(.interactively)
                .navigationTitle(expected == nil ? "Segnala" : "Aggiorna segnalazione")
                .disabled(busy || store.locked || store.isRestoring)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Fine") { focusedField = nil }
                            .accessibilityIdentifier("concern-keyboard-done")
                    }
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Salva") { Task { await save() } }
                            .disabled(busy || store.locked || store.isRestoring || concern.area.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("concern-save")
                    }
                }.interactiveDismissDisabled(busy)
        }
    }
    private func save() async {
        busy = true; defer { busy = false }
        do {
            let result = try await store.saveTrainingConcern(concern, expected: expected)
            concern = result.concern; expected = result.concern
            if result.persisted { dismiss() }
            else { message = "Segnalazione conservata in memoria, ma non ancora su disco. Tieni Pivot aperto e riprova Salva, oppure Riprova nelle Impostazioni." }
        } catch { message = error.localizedDescription }
    }
}
