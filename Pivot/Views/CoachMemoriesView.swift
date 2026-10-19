import SwiftUI

struct CoachMemoriesView: View {
    @EnvironmentObject private var store: PivotStore
    @State private var editing: CoachMemory?
    @State private var deleting: CoachMemory?
    var body: some View {
        List {
            Section {
                Text("Le preferenze restano locali. Scegli esplicitamente quali usare anche con l’AI online: massimo 4, brevi e senza dati sanitari. Puoi modificarle, farle scadere o revocarle.").font(.subheadline)
                Button { editing = CoachMemory(text: "") } label: { Label("Aggiungi preferenza", systemImage: "plus") }
                    .accessibilityIdentifier("coach-memory-add")
            }
            Section("Le tue preferenze") {
                if store.data.coachState.memories.isEmpty { Text("Nessuna preferenza salvata").foregroundStyle(.secondary) }
                ForEach(store.data.coachState.memories) { memory in
                    Button { editing = memory } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(memory.text).foregroundStyle(.primary)
                            Text(!memory.isActive(at: Date()) ? "Scaduta o non ancora attiva" : memory.onlineSharingAllowed == true ? "Locale e AI online" : "Solo sul dispositivo")
                                .font(.caption).foregroundStyle(.secondary)
                            if let until = memory.expiresAt { Text(DisplayDate.label(until, format: "d MMM yyyy HH:mm")).font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("coach-memory-" + memory.id.uuidString)
                    .swipeActions { Button("Elimina", role: .destructive) { deleting = memory } }
                }
            }
        }.navigationTitle("Preferenze di Pivot").navigationBarTitleDisplayMode(.inline).tint(PivotTheme.accent)
            .disabled(store.locked)
            .sheet(item: $editing) { memory in CoachMemoryEditor(memory: memory) }
            .confirmationDialog("Eliminare questa preferenza?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Elimina", role: .destructive) {
                    guard let deleting else { return }
                    if store.change({ $0.coachState.memories.removeAll { $0.id == deleting.id } }) {
                        store.onlineConversationPermission.revoke()
                    }
                    self.deleting = nil
                }
                Button("Annulla", role: .cancel) { deleting = nil }
            }
    }
}

private struct CoachMemoryEditor: View {
    @EnvironmentObject private var store: PivotStore
    @Environment(\.dismiss) private var dismiss
    let memory: CoachMemory
    @State private var text = ""
    @State private var online = false
    @State private var temporary = false
    @State private var until = Date().addingTimeInterval(7 * 86400)
    @State private var problem: String?
    @State private var loaded = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Preferenza") {
                    TextField("Ad esempio: preferisco allenarmi la sera", text: $text, axis: .vertical).lineLimit(3...8)
                        .accessibilityIdentifier("coach-memory-text")
                    Text("\(online ? text.utf16.count : text.count)/\(online ? 240 : 1500)").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Usa anche con l’AI online", isOn: $online).accessibilityIdentifier("coach-memory-online")
                } footer: {
                    Text("Se attivi questa scelta, la preferenza filtrata viene inclusa nei prossimi messaggi online a Cloudflare → Groq. Sarà visibile in Dati inviati. Non aggiungere dolori, infortuni o altri dati sanitari. La revoca interrompe gli invii futuri, non ritira quelli già effettuati.")
                }
                Section {
                    Toggle("Preferenza temporanea", isOn: $temporary).accessibilityIdentifier("coach-memory-temporary")
                    if temporary { DatePicker("Valida fino a", selection: $until, in: Date()...) }
                }
                if let problem { Section { Text(problem).foregroundStyle(PivotTheme.amber).accessibilityIdentifier("coach-memory-error") } }
            }.navigationTitle("Preferenza").navigationBarTitleDisplayMode(.inline).tint(PivotTheme.accent)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Salva") { save() }.disabled(store.locked || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("coach-memory-save") }
                }
                .onAppear {
                    guard !loaded else { return }; loaded = true
                    text = memory.text; online = memory.onlineSharingAllowed == true
                    temporary = memory.expiresAt != nil; if let expiry = memory.expiresAt { until = expiry }
                }
        }
    }
    private func save() {
        var value = memory
        value.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        value.onlineSharingAllowed = online
        value.expiresAt = temporary ? until : nil
        // A restored/expired entry can be edited without inventing a new origin.
        if let expiry = value.expiresAt, expiry <= Date(), expiry != memory.expiresAt {
            problem = "Scegli una scadenza futura."; return
        }
        if let error = CoachMemoryContext.problem(value, replacing: memory.id, in: store.data.coachState.memories) { problem = error; return }
        guard store.change({ data in
            var state = data.coachState
            if let index = state.memories.firstIndex(where: { $0.id == memory.id }) { state.memories[index] = value }
            else { state.memories.append(value) }
            data.coachState = state
        }) else { problem = "Preferenza non salvata. Riprova."; return }
        store.onlineConversationPermission.revoke()
        dismiss()
    }
}
