import SwiftUI

/// Local choices only. Opening, searching or selecting never contacts Maps or
/// writes an event. A saved place is not evidence of the current departure.
struct SavedPlacesView: View {
    @EnvironmentObject private var store: PivotStore
    @Environment(\.dismiss) private var dismiss
    var onSelect: ((SavedPlace) -> Void)? = nil
    @State private var query = ""
    @State private var editing: SavedPlace?
    @State private var removing: SavedPlace?
    @State private var clearing = false
    @State private var problem: String?
    private var library: PlaceLibrary { store.data.placeLibrary ?? PlaceLibrary() }
    private func matches(_ place: SavedPlace) -> Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty || place.name.localizedCaseInsensitiveContains(term) || place.address.localizedCaseInsensitiveContains(term)
    }
    private var contacts: [SavedPlace] {
        store.data.clients.compactMap { client in
            guard let defaults = client.defaults, defaults.place == .studentHome,
                  !defaults.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return SavedPlace(id: client.id, name: client.name, address: defaults.address)
        }.filter(matches).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        List {
            Section("Salvati") {
                ForEach(library.sortedFavorites.filter(matches)) { place in
                    HStack {
                        placeButton(place)
                        Menu {
                            Button("Modifica", systemImage: "pencil") { editing = place }
                            Button("Rimuovi dai salvati", systemImage: "trash", role: .destructive) { removing = place }
                        } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                            .accessibilityLabel("Opzioni per \(place.name)").accessibilityIdentifier("place-actions-\(place.id)")
                    }
                }
                if library.favorites.isEmpty { Text("Salva Casa, Università o un altro luogo.").foregroundStyle(.secondary) }
            }
            if onSelect != nil, !contacts.isEmpty {
                Section("A casa dei contatti") { ForEach(contacts) { placeButton($0) } }
            }
            if !library.recent.isEmpty {
                Section("Recenti") {
                    ForEach(library.recentPlaces.map { SavedPlace($0) }.filter(matches).prefix(8)) { placeButton($0) }
                }
                Section("Più usati") {
                    ForEach(library.frequentPlaces.map { SavedPlace($0) }.filter(matches).prefix(8)) { placeButton($0) }
                }
                Section {
                    Button("Cancella cronologia", role: .destructive) { clearing = true }
                        .accessibilityIdentifier("places-clear-history")
                }
            }
            if let problem { Section { Text(problem).foregroundStyle(PivotTheme.amber) } }
            Section {
                Text("Luoghi e cronologia restano nei dati personali di Pivot. Le ricerche digitate non vengono conservate. La scelta di un luogo non conferma tempi di viaggio né la tua posizione attuale.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Luoghi").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Nome o indirizzo")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = SavedPlace(name: "", address: "") } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Salva un luogo").accessibilityIdentifier("places-add")
                        .disabled(store.locked || store.isLoading || store.isRestoring || library.favorites.count >= PlaceLibrary.maximumFavorites)
                }
                if onSelect != nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } }
                }
            }
            .sheet(item: $editing) { place in
                NavigationStack { SavedPlaceEditor(place: place, editingID: library.favorites.first(where: { $0.id == place.id })?.id) }
            }
            .alert("Rimuovere il luogo salvato?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
                Button("Annulla", role: .cancel) { removing = nil }
                Button("Rimuovi", role: .destructive) {
                    guard let id = removing?.id else { return }
                    modify { try $0.removeFavorite(id: id) }; removing = nil
                }
            } message: { Text("Non cambia eventi, indirizzi dei contatti o cronologia dei luoghi già usati.") }
            .alert("Cancellare la cronologia dei luoghi?", isPresented: $clearing) {
                Button("Annulla", role: .cancel) { }
                Button("Cancella cronologia", role: .destructive) { modify { try $0.clearHistory() } }
            } message: { Text("Rimuove recenti e frequenza d’uso. Conserva luoghi salvati, contatti ed eventi.") }
    }
    private func placeButton(_ place: SavedPlace) -> some View {
        Button {
            if let onSelect { onSelect(place); dismiss() }
            else { editing = place }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name).foregroundStyle(PivotTheme.text)
                Text(place.address).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("place-select-\(place.name)")
    }
    private func modify(_ action: (inout PlaceLibrary) throws -> Void) {
        do {
            var next = library; try action(&next)
            guard store.change({ $0.placeLibrary = next }) else { problem = store.error; return }
            problem = nil
        } catch { problem = error.localizedDescription }
    }
}

struct SavedPlaceEditor: View {
    @EnvironmentObject private var store: PivotStore
    @Environment(\.dismiss) private var dismiss
    let place: SavedPlace
    let editingID: UUID?
    @State private var name: String
    @State private var address: String
    @State private var problem: String?
    @FocusState private var focused: Bool
    init(place: SavedPlace, editingID: UUID?) {
        self.place = place; self.editingID = editingID
        _name = State(initialValue: place.name); _address = State(initialValue: place.address)
    }
    var body: some View {
        Form {
            Section {
                TextField("Nome, es. Casa", text: $name).focused($focused).accessibilityIdentifier("place-name")
                TextField("Indirizzo completo", text: $address).focused($focused)
                    .autocorrectionDisabled().accessibilityIdentifier("place-address")
            } footer: { Text("Se l’indirizzo non è stato scelto da Maps, lo potrai cercare e verificare prima di calcolare il viaggio.") }
            if let problem { Section { Text(problem).foregroundStyle(PivotTheme.amber) } }
        }.navigationTitle(editingID == nil ? "Salva luogo" : "Modifica luogo").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() }.accessibilityIdentifier("place-close") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }.accessibilityIdentifier("place-save")
                        .disabled(store.locked || store.isLoading || store.isRestoring || !input.isValid)
                }
            }.pivotKeyboardToolbar(identifier: "place-keyboard-done") { focused = false }
    }
    private var input: SavedPlace {
        .init(name: name.trimmingCharacters(in: .whitespacesAndNewlines), address: address.trimmingCharacters(in: .whitespacesAndNewlines),
              latitude: address == place.address ? place.latitude : nil, longitude: address == place.address ? place.longitude : nil)
    }
    private func save() {
        do {
            var next = store.data.placeLibrary ?? PlaceLibrary()
            let value = input
            try next.save(name: value.name, address: value.address, latitude: value.latitude, longitude: value.longitude, editingID: editingID)
            guard store.change({ $0.placeLibrary = next }) else { problem = store.error; return }
            dismiss()
        } catch { problem = error.localizedDescription }
    }
}
