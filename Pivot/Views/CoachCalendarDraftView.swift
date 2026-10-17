import SwiftUI

struct CoachCalendarDraftView: View {
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var store: PivotStore
    @Environment(\.dismiss) private var dismiss
    @State var draft: CoachCalendarDraft
    var savedDraftID: UUID? = nil
    var initialCalendarID: String? = nil
    var sourceMessage: String = ""
    var onCreated: (CalendarItem, Bool) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var calendarID = ""
    @State private var conflicts: [CalendarItem] = []
    @State private var confirm = false
    @State private var busy = false
    @State private var problem: String?
    @State private var loaded = false
    @State private var rememberAccount = false
    @State private var rememberTopic = false
    @State private var topic = ""
    @State private var preferenceMessage: String?

    private var choices: [CalendarChoice] {
        calendar.choices.filter { $0.writable && !$0.holiday &&
            !store.data.settings.excludedCalendarIDs.contains($0.id) && !store.data.settings.excludedCalendarTitles.contains($0.title) }
    }
    private var routingChoices: [CoachCalendarRouting.Choice] {
        choices.map { .init(id: $0.id, title: $0.title, sourceID: $0.sourceIdentifier) }
    }
    private var suggestion: CoachCalendarRouting.Suggestion {
        CoachCalendarRouting.suggest(title: draft.title, hint: draft.calendarHint, choices: routingChoices, settings: store.data.settings, context: sourceMessage)
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
                    if suggestion.reason == .missingAccount && calendarID.isEmpty {
                        Text("L’account abituale non è disponibile. Scegli esplicitamente dove salvare: non passo a un altro account.").font(.caption).foregroundStyle(PivotTheme.amber)
                    }
                    TextField("Note o elenco", text: $draft.notes, axis: .vertical).lineLimit(3...12)
                }
                Section {
                    CoachCalendarPreferencesFields(choices: choices, calendarID: calendarID,
                        rememberAccount: $rememberAccount, rememberTopic: $rememberTopic, topic: $topic,
                        message: preferenceMessage, save: { _ = savePreferences() })
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
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { if persistDraft() { dismiss() } }.disabled(busy).accessibilityIdentifier("coach-create-close") } }
                .task {
                    guard !loaded else { return }
                    await calendar.refresh(settings: store.data.settings)
                    if let initialCalendarID {
                        calendarID = choices.contains(where: { $0.id == initialCalendarID }) ? initialCalendarID : ""
                        if calendarID.isEmpty { problem = "Il calendario scelto per questa bozza non è più disponibile. Scegline uno prima di confermare." }
                    } else { calendarID = suggestion.calendarID ?? "" }
                    topic = CoachCalendarRouting.suggestedTopic(title: draft.title, hint: draft.calendarHint)
                    loaded = true
                }
                .onDisappear { _ = persistDraft() }
                .onChange(of: scenePhase) { _, value in if value != .active { _ = persistDraft() } }
                .alert("Creare questo impegno nel Calendario?", isPresented: $confirm) {
                    Button("Crea nel Calendario") { save() }.accessibilityIdentifier("coach-create-confirm")
                    Button("Annulla", role: .cancel) { }
                } message: {
                    Text(conflicts.isEmpty ? "Nessuna sovrapposizione rilevata nei calendari inclusi. Il salvataggio aggiunge un solo evento." :
                        "Si sovrappone a: " + conflicts.map(\.title).joined(separator: ", ") + ". Conferma solo se vuoi mantenere la sovrapposizione.")
                }
        }.interactiveDismissDisabled(busy)
    }
    private func review() {
        guard persistDraft() else { return }
        if let issue = draft.problem(now: Date(), calendarID: calendarID) { problem = issue; return }
        busy = true; problem = nil
        Task {
            defer { busy = false }
            do { conflicts = try await calendar.reviewCreation(draft, calendarID: calendarID, settings: store.data.settings); confirm = true }
            catch { problem = error.localizedDescription }
        }
    }
    @discardableResult private func persistDraft() -> Bool {
        guard loaded, let savedDraftID else { return true }
        guard let existing = store.data.coachState.calendarDrafts?.first(where: { $0.id == savedDraftID }) else {
            problem = "La bozza non è più nello storico. Non ho creato altri impegni."; return false
        }
        if existing.createdEventID != nil { return true }
        if existing.draft == draft && existing.calendarID == (calendarID.isEmpty ? nil : calendarID) { return true }
        var next = store.data
        guard CoachDraftStore.update(id: savedDraftID, draft: draft, calendarID: calendarID.isEmpty ? nil : calendarID, data: &next) else {
            problem = "Non riesco a salvare queste modifiche alla bozza. Controlla la lunghezza del titolo, delle note e gli orari."; return false
        }
        return store.change { $0 = next }
    }
    @discardableResult private func savePreferences() -> Bool {
        guard rememberAccount || rememberTopic else { return true }
        var settings = store.data.settings
        do {
            try CoachCalendarRouting.remember(topic: rememberTopic ? topic : nil, calendarID: calendarID,
                rememberAccount: rememberAccount, choices: routingChoices, settings: &settings)
            guard store.change({ $0.settings = settings }) else { return false }
            rememberAccount = false; rememberTopic = false
            preferenceMessage = "Preferenze salvate su questo iPhone."
            return true
        } catch { preferenceMessage = "Scegli un calendario disponibile e un’associazione di massimo 80 caratteri."; return false }
    }
    private func save() {
        busy = true; problem = nil
        Task {
            defer { busy = false }
            do {
                // Validate preferences before the external write. Learning is
                // applied only after creation, or by its separate explicit button.
                if rememberAccount || rememberTopic {
                    var settings = store.data.settings
                    try CoachCalendarRouting.remember(topic: rememberTopic ? topic : nil, calendarID: calendarID,
                        rememberAccount: rememberAccount, choices: routingChoices, settings: &settings)
                }
                let result = try await calendar.create(draft, calendarID: calendarID, expectedConflicts: conflicts, settings: store.data.settings)
                store.change {
                    $0.settings.preferredNewEventCalendarID = calendarID
                    if let hint = draft.calendarHint, !CoachCalendarDraft.normalizedCalendarHint(hint).isEmpty {
                        var aliases = $0.settings.calendarCreationAliases ?? [:]
                        aliases[CoachCalendarDraft.normalizedCalendarHint(hint)] = calendarID
                        $0.settings.calendarCreationAliases = aliases
                    }
                }
                _ = savePreferences()
                onCreated(result.item, result.existing); dismiss()
            } catch { problem = error.localizedDescription }
        }
    }
}
