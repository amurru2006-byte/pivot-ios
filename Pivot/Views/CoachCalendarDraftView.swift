import SwiftUI

struct CoachCalendarDraftView: View {
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var store: PivotStore
    @Environment(\.dismiss) private var dismiss
    @State var draft: CoachCalendarDraft
    var onCreated: (CalendarItem, Bool) -> Void
    @State private var calendarID = ""
    @State private var conflicts: [CalendarItem] = []
    @State private var confirm = false
    @State private var busy = false
    @State private var problem: String?

    private var choices: [CalendarChoice] {
        calendar.choices.filter { $0.writable && !$0.holiday &&
            !store.data.settings.excludedCalendarIDs.contains($0.id) && !store.data.settings.excludedCalendarTitles.contains($0.title) }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Bozza, non ancora salvata") {
                    TextField("Titolo", text: $draft.title).accessibilityIdentifier("coach-create-title")
                    if draft.start != nil {
                        DatePicker("Inizio", selection: Binding(get: { draft.start! }, set: { draft.start = $0 }))
                    } else { Button("Imposta inizio") { draft.start = Date().addingTimeInterval(3600) } }
                    if draft.end != nil {
                        DatePicker("Fine", selection: Binding(get: { draft.end! }, set: { draft.end = $0; draft.endEstimated = false }))
                    } else { Button("Imposta fine") { draft.end = (draft.start ?? Date()).addingTimeInterval(3600); draft.endEstimated = true } }
                    if draft.endEstimated { Text("La fine è una stima: controllala prima di confermare.").foregroundStyle(PivotTheme.amber) }
                    Picker("Calendario", selection: $calendarID) {
                        Text("Scegli calendario").tag("")
                        ForEach(choices) { choice in
                            Text(choice.title + (choice.sourceTitle.isEmpty ? "" : " · " + choice.sourceTitle)).tag(choice.id)
                        }
                    }.accessibilityIdentifier("coach-create-calendar")
                    if let hint = draft.calendarHint, calendarID.isEmpty {
                        Text("Hai indicato ‘\(hint)’. Scegli il calendario corrispondente: non ne seleziono uno ambiguo.").font(.caption)
                    }
                    TextField("Note o elenco", text: $draft.notes, axis: .vertical).lineLimit(3...12)
                }
                if let problem { Section { Text(problem).foregroundStyle(PivotTheme.amber) } }
                Section {
                    Button(busy ? "Verifico…" : "Verifica e prepara il salvataggio") { review() }
                        .disabled(busy || store.locked || !calendar.hasAccess)
                        .accessibilityIdentifier("coach-create-review")
                    if !calendar.hasAccess { Text("Serve l'accesso completo ai calendari nelle Impostazioni di iOS.").font(.caption) }
                }
            }.disabled(busy)
                .navigationTitle("Nuovo impegno")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() }.disabled(busy) } }
                .task {
                    await calendar.refresh(settings: store.data.settings)
                    let matches = CoachCalendarDraft.matchingCalendarIDs(hint: draft.calendarHint, choices: choices.map { ($0.id, $0.title) })
                    if matches.count == 1 { calendarID = matches[0] }
                    else if draft.calendarHint == nil, let preferred = store.data.settings.preferredNewEventCalendarID,
                            choices.contains(where: { $0.id == preferred }) { calendarID = preferred }
                    else if draft.calendarHint == nil, choices.count == 1 { calendarID = choices[0].id }
                }
                .confirmationDialog("Creare questo impegno nel Calendario?", isPresented: $confirm, titleVisibility: .visible) {
                    Button("Crea nel Calendario") { save() }.accessibilityIdentifier("coach-create-confirm")
                    Button("Annulla", role: .cancel) { }
                } message: {
                    Text(conflicts.isEmpty ? "Nessuna sovrapposizione rilevata nei calendari inclusi. Il salvataggio aggiunge un solo evento." :
                        "Si sovrappone a: " + conflicts.map(\.title).joined(separator: ", ") + ". Conferma solo se vuoi mantenere la sovrapposizione.")
                }
        }.interactiveDismissDisabled(busy)
    }
    private func review() {
        if let issue = draft.problem(now: Date(), calendarID: calendarID) { problem = issue; return }
        busy = true; problem = nil
        Task {
            defer { busy = false }
            do { conflicts = try await calendar.reviewCreation(draft, calendarID: calendarID, settings: store.data.settings); confirm = true }
            catch { problem = error.localizedDescription }
        }
    }
    private func save() {
        busy = true; problem = nil
        Task {
            defer { busy = false }
            do {
                let result = try await calendar.create(draft, calendarID: calendarID, expectedConflicts: conflicts, settings: store.data.settings)
                store.change { $0.settings.preferredNewEventCalendarID = calendarID }
                onCreated(result.item, result.existing); dismiss()
            } catch { problem = error.localizedDescription }
        }
    }
}
