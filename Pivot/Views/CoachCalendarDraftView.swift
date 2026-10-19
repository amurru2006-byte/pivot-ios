import SwiftUI

enum CoachCalendarDraftField: Hashable { case title, notes, topic, location }

struct CoachCalendarDraftView: View {
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var store: PivotStore
    @Environment(\.dismiss) private var dismiss
    @State var draft: CoachCalendarDraft
    var savedDraftID: UUID? = nil
    var initialCalendarID: String? = nil
    var sourceMessage: String = ""
    var initialOptions: CalendarCreationOptions = .init()
    var initialNeedsVerification: Bool = false
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
    @State private var options = CalendarCreationOptions()
    @State private var needsVerification = false
    @State private var showTravel = false
    @FocusState private var focusedField: CoachCalendarDraftField?

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
    private var historical: Bool { draft.start.map { $0 < Date().addingTimeInterval(-60) } ?? false }
    var body: some View {
        NavigationStack {
            Form {
                if needsVerification {
                    Section {
                        Label("Verifica il salvataggio precedente", systemImage: "exclamationmark.triangle")
                        Text("L’attività o lo spostamento potrebbero essere già nel Calendario. Questa verifica legge soltanto: non crea copie e non cambia gli eventi.").font(.subheadline)
                        Button("Verifica esito nel Calendario") { save(verifyOnly: true) }
                            .accessibilityIdentifier("creation-verify-result")
                    }
                }
                Group {
                Section {
                    TextField("Titolo", text: $draft.title).font(.title3)
                        .focused($focusedField, equals: .title).accessibilityIdentifier("coach-create-title")
                    TextField("Posizione", text: $options.location)
                        .focused($focusedField, equals: .location).accessibilityIdentifier("creation-location")
                }
                Section {
                    if historical {
                        Label("Registrazione nel passato", systemImage: "clock.arrow.circlepath").foregroundStyle(PivotTheme.accent)
                        Text("Gli orari resteranno quelli indicati, senza spostare la data a domani o cancellare altri impegni.").font(.caption)
                    }
                    if draft.start != nil {
                        DatePicker("Inizio", selection: Binding(get: { draft.start! }, set: { draft.start = $0 }))
                            .accessibilityIdentifier("creation-start")
                    } else { Button("Imposta inizio") { draft.start = Date().addingTimeInterval(3600) } }
                    if draft.end != nil {
                        DatePicker("Fine", selection: Binding(get: { draft.end! }, set: { draft.end = $0; draft.endEstimated = false }))
                    } else { Button("Imposta fine") { draft.end = (draft.start ?? Date()).addingTimeInterval(3600); draft.endEstimated = true } }
                    if draft.endEstimated { Text("La fine è una stima: controllala prima di confermare.").foregroundStyle(PivotTheme.amber) }
                    Button { focusedField = nil; showTravel = true } label: {
                        HStack {
                            Label("Tempo di percorrenza", systemImage: "figure.walk")
                            Spacer()
                            Text(options.travel.map { "\($0.minutes) min" } ?? "Nessuno").foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.foregroundStyle(.primary)
                    }.accessibilityIdentifier("creation-travel-open")
                }
                Section {
                    CalendarCreationPreview(draft: draft, options: options, color: PivotTheme.accent)
                }
                Section("Opzioni") {
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
                    Picker(selection: $options.availability) {
                        Text("Non disponibile").tag(0)
                        Text("Disponibile").tag(1)
                    } label: { Label("Mostra come", systemImage: "hand.raised") }
                    Picker(selection: $options.alertMinutes) {
                        Text("Nessuno").tag(nil as Int?)
                        ForEach([0, 5, 10, 15, 30, 60, 120, 1440], id: \.self) { value in
                            Text(value == 0 ? "All’inizio" : (value == 1440 ? "1 giorno prima" : "\(value) min prima")).tag(Optional(value))
                        }
                    } label: { Label("Avviso", systemImage: "bell") }
                }
                Section {
                    TextField("Note o elenco", text: $draft.notes, axis: .vertical).lineLimit(3...12)
                        .focused($focusedField, equals: .notes)
                }
                Section {
                    CoachCalendarPreferencesFields(choices: choices, calendarID: calendarID,
                        rememberAccount: $rememberAccount, rememberTopic: $rememberTopic, topic: $topic,
                        focusedField: $focusedField, message: preferenceMessage, save: { _ = savePreferences() })
                }
                }.disabled(needsVerification)
                if let problem { Section { Text(problem).foregroundStyle(PivotTheme.amber) } }
                Section {
                    Button(busy ? "Verifico…" : "Verifica e prepara il salvataggio") { review() }
                        .disabled(busy || needsVerification || store.locked || !calendar.hasAccess)
                        .accessibilityIdentifier("coach-create-review")
                    if !calendar.hasAccess { Text("Serve l'accesso completo ai calendari nelle Impostazioni di iOS.").font(.caption) }
                }
            }.disabled(busy).scrollDismissesKeyboard(.interactively)
                .tint(PivotTheme.accent).listSectionSpacing(20)
                .navigationTitle("Nuovo impegno")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { closeDraft() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Chiudi").disabled(busy).accessibilityIdentifier("coach-create-close")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button { review() } label: { Image(systemName: "checkmark") }.accessibilityLabel("Verifica e salva")
                            .disabled(busy || needsVerification || store.locked || !calendar.hasAccess).accessibilityIdentifier("creation-top-save")
                    }
                }
                .pivotKeyboardToolbar(identifier: "coach-draft-keyboard-done") { focusedField = nil }
                .task {
                    guard !loaded else { return }
                    await calendar.refresh(settings: store.data.settings)
                    if let initialCalendarID {
                        calendarID = choices.contains(where: { $0.id == initialCalendarID }) ? initialCalendarID : ""
                        if calendarID.isEmpty { problem = "Il calendario scelto per questa bozza non è più disponibile. Scegline uno prima di confermare." }
                    } else { calendarID = suggestion.calendarID ?? "" }
                    options = initialOptions; needsVerification = initialNeedsVerification
                    topic = CoachCalendarRouting.suggestedTopic(title: draft.title, hint: draft.calendarHint)
                    loaded = true
                }
                .onDisappear { _ = persistDraft() }
                .onChange(of: scenePhase) { _, value in if value != .active { _ = persistDraft() } }
                .alert("Creare questo impegno nel Calendario?", isPresented: $confirm) {
                    Button(options.travel == nil ? "Crea nel Calendario" : "Crea attività e spostamento") { save() }.accessibilityIdentifier("coach-create-confirm")
                    Button("Annulla", role: .cancel) { }
                } message: {
                    Text((historical ? "Stai registrando un evento nel passato. " : "") +
                        (options.travel == nil ? "Aggiungerò un evento. " : "Aggiungerò due eventi nello stesso calendario: attività e Spostamento. " ) +
                        (conflicts.isEmpty ? "Nessuna sovrapposizione rilevata nei calendari inclusi per questi orari, compreso il viaggio scelto." :
                        "Si sovrappone a: " + conflicts.map(\.title).joined(separator: ", ") + ". Conferma solo se vuoi mantenere la sovrapposizione.")
                    )
                }
                .sheet(isPresented: $showTravel) {
                    CalendarTravelEditor(options: options, start: draft.start, suggestedOrigin: suggestedOrigin) { options = $0 }
                }
        }.interactiveDismissDisabled(busy)
    }
    private func closeDraft() {
        guard !busy, persistDraft() else { return }
        busy = true
        Task { @MainActor in
            let persisted = await store.flushPendingWrites()
            busy = false
            if persisted { dismiss() }
            else { problem = "La bozza è ancora in memoria, ma non è salvata su disco. Riprova prima di chiudere Pivot." }
        }
    }
    private func review() {
        guard persistDraft() else { return }
        if let issue = draft.problem(now: Date(), calendarID: calendarID) { problem = issue; return }
        if let issue = options.problem(draft: draft, now: Date(), mapsConsent: AppleMapsService.shared.consentGranted) { problem = issue; return }
        busy = true; problem = nil
        Task {
            defer { busy = false }
            guard await store.flushPendingWrites() else {
                problem = "Completa il salvataggio della bozza prima di creare l’impegno. Nessun evento è stato creato."
                return
            }
            do { conflicts = try await calendar.reviewCreation(draft, calendarID: calendarID, settings: store.data.settings,
                options: options, creationID: savedDraftID); confirm = true }
            catch { problem = error.localizedDescription }
        }
    }
    @discardableResult private func persistDraft() -> Bool {
        guard loaded, let savedDraftID else { return true }
        guard let existing = store.data.coachState.calendarDrafts?.first(where: { $0.id == savedDraftID }) else {
            problem = "La bozza non è più nello storico. Non ho creato altri impegni."; return false
        }
        if existing.createdEventID != nil { return true }
        if existing.draft == draft && existing.calendarID == (calendarID.isEmpty ? nil : calendarID)
            && (existing.creationOptions ?? .init()) == options { return true }
        var next = store.data
        guard CoachDraftStore.update(id: savedDraftID, draft: draft, calendarID: calendarID.isEmpty ? nil : calendarID, data: &next, options: options) else {
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
    private var suggestedOrigin: String {
        guard let start = draft.start else { return "" }
        return CalendarCreationBundle.suggestedOrigin(before: start, events: calendar.events)
    }
    private func save(verifyOnly: Bool = false) {
        guard !busy, !store.locked, !store.isRestoring, store.beginCalendarMutation() else { return }
        busy = true; problem = nil
        Task {
            defer { busy = false; store.endCalendarMutation() }
            do {
                // Validate preferences before the external write. Learning is
                // applied only after creation, or by its separate explicit button.
                if rememberAccount || rememberTopic {
                    var settings = store.data.settings
                    try CoachCalendarRouting.remember(topic: rememberTopic ? topic : nil, calendarID: calendarID,
                        rememberAccount: rememberAccount, choices: routingChoices, settings: &settings)
                }
                if !verifyOnly {
                    guard persistDraft(), let savedDraftID, store.change({ data in
                        if let index = data.coachState.calendarDrafts?.firstIndex(where: { $0.id == savedDraftID }) {
                            data.coachState.calendarDrafts?[index].creationNeedsVerification = true
                        }
                    }), await store.flushPendingWrites() else { throw CalendarFailure.archiveNotSaved }
                    needsVerification = true
                }
                let result = try await calendar.create(draft, calendarID: calendarID, expectedConflicts: conflicts, settings: store.data.settings,
                    options: options, creationID: savedDraftID, verifyOnly: verifyOnly)
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
            } catch {
                // A revalidation refusal proves no EventKit write began. Keep
                // uncertain commit outcomes locked to read-only reconciliation.
                if !verifyOnly, (error as? CalendarFailure)?.stoppedBeforeCalendarWrite == true, let savedDraftID {
                    if store.change({ data in
                        if let index = data.coachState.calendarDrafts?.firstIndex(where: { $0.id == savedDraftID }) {
                            data.coachState.calendarDrafts?[index].creationNeedsVerification = false
                        }
                    }), await store.flushPendingWrites() { needsVerification = false }
                }
                problem = error.localizedDescription
            }
        }
    }
}
