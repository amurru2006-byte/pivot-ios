import SwiftUI

struct TrainingPlanEditor: View {
    @EnvironmentObject private var store: PivotStore
    @Environment(\.dismiss) private var dismiss
    let planID: UUID?
    @State private var payload: TrainingPlanPayload
    @State private var changeNote = ""
    @State private var selecting = false
    @State private var dayIndex = 0
    @State private var replacingID: String?
    @State private var message: String?
    init(plan: TrainingPlan? = nil) {
        planID = plan?.id
        _payload = State(initialValue: plan?.payload ?? TrainingPlanPayload(formatVersion: 1, name: "Nuovo obiettivo", days: [TrainingDay(id: UUID().uuidString, name: "Giorno A", exercises: [])]))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(planID == nil ? "Nuova scheda / nuovo obiettivo" : "Modifica la scheda") {
                    TextField("Nome della scheda", text: $payload.name).accessibilityIdentifier("training-plan-name")
                    TextField("Motivo / indicazioni del coach", text: $changeNote, axis: .vertical)
                    Text("I vecchi allenamenti restano invariati. Le modifiche si applicano alle nuove sessioni, non a quelle già iniziate.").font(.caption)
                }
                ForEach(payload.days.indices, id: \.self) { index in
                    Section {
                        TextField("Nome del giorno", text: $payload.days[index].name)
                        ForEach(payload.days[index].exercises.indices, id: \.self) { exerciseIndex in
                            DisclosureGroup(payload.days[index].exercises[exerciseIndex].name) {
                                TextField("Nome visualizzato (stesso esercizio)", text: $payload.days[index].exercises[exerciseIndex].name)
                                Stepper("Serie: \(payload.days[index].exercises[exerciseIndex].sets)", value: $payload.days[index].exercises[exerciseIndex].sets, in: 1...30)
                                TextField("Ripetizioni", text: $payload.days[index].exercises[exerciseIndex].reps)
                                Stepper("Recupero: \(payload.days[index].exercises[exerciseIndex].restSeconds) sec", value: $payload.days[index].exercises[exerciseIndex].restSeconds, in: 0...3600, step: 15)
                                TextField("Note del coach", text: $payload.days[index].exercises[exerciseIndex].coachNotes, axis: .vertical)
                                Button("Sostituisci con un altro esercizio") { dayIndex = index; replacingID = payload.days[index].exercises[exerciseIndex].id; selecting = true }
                                Button("Rimuovi dalla scheda", role: .destructive) { payload.days[index].exercises.remove(at: exerciseIndex) }
                                Text("Rinominare mantiene lo stesso storico. Per cambiare variante usa Sostituisci: esercizi differenti non condividono automaticamente le statistiche.").font(.caption)
                            }
                        }.onMove { payload.days[index].exercises.move(fromOffsets: $0, toOffset: $1) }
                        Button("Aggiungi esercizio") { dayIndex = index; replacingID = nil; selecting = true }.disabled(payload.days[index].exercises.count >= 40)
                        if payload.days.count > 1 { Button("Rimuovi giorno", role: .destructive) { payload.days.remove(at: index) } }
                    } header: { Text(payload.days[index].name) }
                }
                EditButton()
                Button("Aggiungi giorno") { payload.days.append(TrainingDay(id: UUID().uuidString, name: "Nuovo giorno", exercises: [])) }.disabled(payload.days.count >= 14)
                if let message { Text(message).foregroundStyle(PivotTheme.amber) }
                Button("Salva scheda") { save() }.disabled(store.locked).accessibilityIdentifier("training-plan-save-bottom")
            }.pivotForm().scrollDismissesKeyboard(.interactively).navigationTitle(planID == nil ? "Nuova scheda" : "Modifica scheda")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Salva") { save() }.disabled(store.locked).accessibilityIdentifier("training-plan-save") }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Fine") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                    }
                }
                .sheet(isPresented: $selecting) {
                    ExercisePickerView { exercise in
                        guard payload.days.indices.contains(dayIndex) else { selecting = false; return }
                        var exercises = payload.days[dayIndex].exercises
                        guard !exercises.contains(where: { $0.id == exercise.id && $0.id != replacingID }) else { message = "Questo esercizio è già presente nel giorno scelto."; selecting = false; return }
                        if let id = replacingID, let index = exercises.firstIndex(where: { $0.id == id }) { exercises[index] = exercise }
                        else { exercises.append(exercise) }
                        payload.days[dayIndex].exercises = exercises; selecting = false
                    }
                }
        }
    }
    private func save() {
        do {
            try payload.validate()
            if let planID {
                var library = store.data.training ?? TrainingLibrary()
                try TrainingEdits.revise(planID: planID, payload: payload, note: changeNote, library: &library)
                guard store.change({ $0.training = library }) else { return }
            } else {
                try store.installTrainingPlan(TrainingPlan(payload: payload, document: nil))
            }
            dismiss()
        } catch { message = "Controlla la scheda: ogni giorno deve avere almeno un esercizio, con nome, serie e ripetizioni. " + error.localizedDescription }
    }
}

struct TrainingRevisionsView: View {
    @EnvironmentObject private var store: PivotStore
    let planID: UUID
    @State private var message: String?
    private var plan: TrainingPlan? { store.data.training?.plans.first { $0.id == planID } }
    var body: some View {
        PivotScreen {
            Text("Ogni modifica conserva la versione precedente; gli allenamenti già registrati non vengono riscritti.").font(.subheadline)
            ForEach(Array((plan?.revisions ?? []).reversed())) { revision in
                PivotCard {
                    Text(DisplayDate.label(revision.date, format: "d MMM yyyy HH:mm")).font(.headline)
                    Text(revision.payload.name)
                    if !revision.note.isEmpty { Text(revision.note).font(.caption).foregroundStyle(PivotTheme.blue) }
                    ForEach(revision.payload.days) { day in
                        Text(day.name + ": " + day.exercises.map { "\($0.name) \($0.sets)×\($0.reps)" }.joined(separator: " · ")).font(.caption)
                    }
                    Button("Ripristina questa versione") {
                        do {
                            var library = store.data.training ?? TrainingLibrary()
                            try TrainingEdits.revise(planID: planID, payload: revision.payload, note: "Ripristino versione precedente", library: &library)
                            if store.change({ $0.training = library }) { message = "Scheda ripristinata; storico conservato." }
                        } catch { message = error.localizedDescription }
                    }.buttonStyle(PivotSecondaryButton()).disabled(store.locked)
                }
            }
            if let message { Text(message).foregroundStyle(PivotTheme.amber) }
        }.navigationTitle("Versioni della scheda")
    }
}
