import SwiftUI

struct CoachDocumentReviewView: View {
    let batchID: UUID
    @EnvironmentObject private var store: PivotStore
    @State private var activeID: UUID?
    @State private var selected = Set<UUID>()
    @State private var editor: CoachDocumentEventProposal?
    @State private var viewer: CoachDocumentDestination?
    @State private var savedDraft: CoachSavedCalendarDraft?
    @State private var busy = false
    @State private var message: String?
    private var batch: CoachDocumentReviewBatch? { store.data.coachDocumentReviews?.first { $0.id == (activeID ?? batchID) } }
    private var sourcesCurrent: Bool { batch?.packet.isCurrent(in: store.data.coachDocuments ?? []) == true }
    var body: some View {
        List {
            if let batch {
                Section {
                    Text(batch.packet.instruction)
                    Text("Riconoscimento locale limitato: una data AAAA-MM-GG per riga e intervalli HH:mm espliciti. Non interpreta liberamente PDF, tabelle o metodiche e non ha contattato un’IA.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(batch.events.count) proposte · \(batch.stagedProposalIDs.count) bozze preparate")
                        .accessibilityIdentifier("coach-document-review-audit")
                    if batch.parentReviewID != nil {
                        Text("Risposta importata: anche con citazioni corrette, controlla l’interpretazione nell’originale.").font(.caption)
                    }
                    if batch.stagedProposalIDs.isEmpty {
                        NavigationLink { CoachDocumentExchangeView(batchID: batch.id) } label: {
                            Label("Elaborazione con ChatGPT · passaggio manuale", systemImage: "arrow.up.doc")
                        }.disabled(busy || !sourcesCurrent).accessibilityIdentifier("coach-document-exchange-open")
                    }
                    if !sourcesCurrent {
                        Text("Le fonti hanno una nuova copia locale. Le vecchie letture restano consultabili; prima di preparare bozze devi rileggerle.").foregroundStyle(.orange)
                        Button("Rileggi queste pagine") { Task { await reread(batch) } }.disabled(busy)
                    }
                }
                if !batch.questions.isEmpty {
                    Section("Da chiarire nella lettura") {
                        ForEach(Array(batch.questions.enumerated()), id: \.offset) { _, text in Text(text).foregroundStyle(.orange) }
                    }
                }
                Section("Proposte da confrontare con le fonti") {
                    ForEach(batch.events) { event in
                        VStack(alignment: .leading, spacing: 10) {
                            if let existing = CoachDocumentReviewStore.preparedDraftID(for: event, in: store.data) {
                                Text(event.title).font(.headline)
                                if let draft = store.data.coachState.calendarDrafts?.first(where: { $0.id == existing }) {
                                    if draft.createdEventID == nil {
                                        Button("Apri bozza salvata") { savedDraft = draft }
                                            .accessibilityIdentifier("coach-document-open-draft-" + existing.uuidString)
                                    } else { Text("Evento già creato: nessuna seconda creazione.").font(.caption) }
                                } else { Text("Bozza già preparata e rimossa dallo storico: non viene ricreata automaticamente.").font(.caption) }
                            } else {
                                Toggle(isOn: Binding(get: { selected.contains(event.id) }, set: {
                                    if $0 { selected.insert(event.id) } else { selected.remove(event.id) }
                                })) { Text(event.title).font(.headline) }
                                .disabled(busy || !sourcesCurrent || needsClarification(event))
                                .accessibilityIdentifier("coach-document-proposal-select-" + event.id.uuidString)
                                Text(summary(event)).font(.subheadline)
                                ForEach(Array(event.questions.enumerated()), id: \.offset) { _, question in Text(question).font(.caption).foregroundStyle(.orange) }
                                Button("Rivedi o chiarisci i dati") { editor = event }.disabled(busy || !sourcesCurrent)
                            }
                            ForEach(Array(event.citations.enumerated()), id: \.offset) { _, citation in
                                Text("“\(citation.quote)”").font(.caption).textSelection(.enabled)
                                Button("Apri fonte · pagina \(citation.page)") { viewer = .init(sourceID: citation.sourceID, page: citation.page) }
                                    .disabled(busy)
                            }
                        }.padding(.vertical, 6)
                    }
                }
                Section {
                    Text("Prepara soltanto bozze in Pivot. Per ciascuna sceglierai il Calendario e confermerai separatamente la creazione. I riferimenti ai documenti saranno nelle note.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Prepara \(selected.count) bozze selezionate") { Task { await stage(batch) } }
                        .disabled(busy || !sourcesCurrent || selected.isEmpty)
                        .accessibilityIdentifier("coach-document-stage")
                }
                Section("Lettura conservata") {
                    ForEach(batch.packet.sources) { source in
                        DisclosureGroup(source.document.name) {
                            Text(batch.packet.coverage(for: source.id) ?? "").font(.caption)
                            ForEach(batch.packet.pages.filter { $0.sourceID == source.id }, id: \.number) { page in
                                DisclosureGroup("Pagina \(page.number)") {
                                    Text(page.text.isEmpty ? "Pagina non leggibile: contenuto non ricostruito." : page.text).textSelection(.enabled)
                                    Button("Apri originale") { viewer = .init(sourceID: source.id, page: page.number) }
                                }
                            }
                        }
                    }
                }
            } else { Text("Questa lettura non è più presente nell’archivio.") }
            if busy { ProgressView("Salvataggio…") }
            if let message { Text(message).accessibilityIdentifier("coach-document-review-status") }
        }
        .navigationTitle("Proposte da documenti")
        .sheet(item: $viewer) { CoachDocumentViewer(destination: $0) }
        .sheet(item: $editor) { event in
            if let batch { NavigationStack { CoachDocumentProposalEditor(batch: batch, event: event) } }
        }
        .sheet(item: $savedDraft) { saved in
            CoachCalendarDraftView(draft: saved.draft, savedDraftID: saved.id, initialCalendarID: saved.calendarID,
                sourceMessage: "Proposta da documenti: controlla l’originale.", initialOptions: saved.creationOptions ?? .init(),
                initialNeedsVerification: saved.creationNeedsVerification == true) { _, _ in savedDraft = nil }
        }
    }
    private func needsClarification(_ event: CoachDocumentEventProposal) -> Bool {
        if case .needsClarification = event.timing { return true }; return false
    }
    private func summary(_ event: CoachDocumentEventProposal) -> String {
        switch event.timing {
        case .allDay(let day): return "Tutto il giorno · \(day)"
        case .timed(let start, let end): return "\(PivotDate.shortDate(start)) · \(PivotDate.time(start))–\(PivotDate.time(end)) · Europe/Rome"
        case .needsClarification(let text): return text
        }
    }
    @MainActor private func stage(_ expected: CoachDocumentReviewBatch) async {
        busy = true; message = nil; defer { busy = false }
        do {
            let ordered = expected.events.map(\.id).filter { selected.contains($0) }
            let ids = try await store.stageCoachDocumentProposals(expected, selected: ordered)
            selected.removeAll(); message = "\(ids.count) bozze salvate in Pivot. Nessun evento è stato creato nel Calendario."
        } catch { message = error.localizedDescription }
    }
    @MainActor private func reread(_ expected: CoachDocumentReviewBatch) async {
        busy = true; message = nil; defer { busy = false }
        do { activeID = try await store.rereadCoachDocumentReview(expected); selected.removeAll() }
        catch { message = error.localizedDescription }
    }
}

private struct CoachDocumentProposalEditor: View {
    @State var batch: CoachDocumentReviewBatch
    @State var event: CoachDocumentEventProposal
    @EnvironmentObject private var store: PivotStore
    @Environment(\.dismiss) private var dismiss
    @State private var checked = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            Section("Dati da verificare") {
                TextField("Titolo", text: $event.title)
                Toggle("Tutto il giorno", isOn: Binding(get: { event.kind == .allDay }, set: {
                    event.kind = $0 ? .allDay : .timed
                    event.startClock = nil; event.endClock = nil; event.endDay = nil; checked = false
                }))
                TextField("Data AAAA-MM-GG", text: Binding(get: { event.day ?? "" }, set: { event.day = $0 }))
                if event.kind == .timed {
                    TextField("Inizio HH:mm", text: Binding(get: { event.startClock ?? "" }, set: { event.startClock = $0 }))
                    TextField("Fine HH:mm", text: Binding(get: { event.endClock ?? "" }, set: { event.endClock = $0 }))
                    TextField("Giorno di fine AAAA-MM-GG", text: Binding(get: { event.endDay ?? event.day ?? "" }, set: { event.endDay = $0.isEmpty ? nil : $0 }))
                    Text("Orari nel fuso Europe/Rome. Se la fonte usa un altro fuso, inserisci gli orari corretti; Pivot non li ha convertiti per ipotesi.").font(.caption)
                }
                TextField("Note", text: $event.notes, axis: .vertical)
            }.disabled(busy)
            Section("Fonte e chiarimenti") {
                ForEach(Array(event.citations.enumerated()), id: \.offset) { _, quote in Text("Pagina \(quote.page): \(quote.quote)").font(.caption) }
                ForEach(Array(event.questions.enumerated()), id: \.offset) { _, text in Text(text).foregroundStyle(.orange) }
                Toggle("Ho verificato nell’originale titolo, anno, data, orari e fuso, risolvendo i dubbi indicati", isOn: $checked).disabled(busy)
            }
            if let error { Text(error).foregroundStyle(.orange) }
            Button("Salva chiarimenti nella proposta") { Task { await save() } }.disabled(!checked || busy)
        }
        .navigationTitle("Rivedi proposta")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() }.disabled(busy) } }
        .interactiveDismissDisabled(busy)
    }
    @MainActor private func save() async {
        busy = true; defer { busy = false }
        var checkedEvent = event; checkedEvent.questions = []
        if case .needsClarification(let reason) = checkedEvent.timing { error = reason; return }
        do { try await store.updateCoachDocumentProposal(batch: batch, event: checkedEvent); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
