import SwiftUI

struct CoachCalendarPreferencesFields: View {
    @EnvironmentObject private var store: PivotStore
    let choices: [CalendarChoice]
    let calendarID: String
    @Binding var rememberAccount: Bool
    @Binding var rememberTopic: Bool
    @Binding var topic: String
    let message: String?
    var save: () -> Void
    @State private var removingTopic: String?
    @State private var confirmRemoval = false
    private var selected: CalendarChoice? { choices.first { $0.id == calendarID } }
    private var preferredAccount: String? {
        guard let source = store.data.settings.preferredNewEventSourceID else { return nil }
        return choices.first { $0.sourceIdentifier == source }?.sourceTitle ?? "Non disponibile"
    }
    var body: some View {
        DisclosureGroup("Preferenze calendario") {
            if let preferredAccount { Text("Account abituale: \(preferredAccount)").font(.caption).accessibilityIdentifier("coach-routing-account") }
            if let selected, !selected.sourceIdentifier.isEmpty {
                Toggle("Usa l’account di questo calendario per i nuovi impegni", isOn: $rememberAccount)
                    .accessibilityIdentifier("coach-routing-remember-account")
                Text(selected.sourceTitle).font(.caption).foregroundStyle(PivotTheme.muted)
            }
            Toggle("Ricorda un’associazione", isOn: $rememberTopic).accessibilityIdentifier("coach-routing-remember-topic")
            if rememberTopic {
                TextField("Quando parlo di…", text: $topic).accessibilityIdentifier("coach-routing-topic")
                Text("Proporrò il calendario selezionato quando queste parole compaiono nel titolo o nella richiesta. Puoi correggere la scelta prima di salvare.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
            }
            Button("Ricorda senza creare l’impegno", action: save)
                .disabled(store.locked || calendarID.isEmpty || (!rememberAccount && !rememberTopic))
                .accessibilityIdentifier("coach-routing-save")
            if let message { Text(message).font(.caption).foregroundStyle(PivotTheme.accent) }
            savedAssociations
        }.confirmationDialog("Dimenticare questa associazione?", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("Dimentica", role: .destructive) {
                if let removingTopic { store.change { $0.settings.calendarTopicRoutes?.removeValue(forKey: removingTopic) } }
                removingTopic = nil
            }
            Button("Annulla", role: .cancel) { removingTopic = nil }
        }
    }
    private var savedAssociations: some View {
        ForEach((store.data.settings.calendarTopicRoutes ?? [:]).keys.sorted(), id: \.self) { key in
            HStack {
                let id = store.data.settings.calendarTopicRoutes?[key]
                Text(key + " → " + (choices.first { $0.id == id }?.title ?? "Calendario non disponibile")).font(.caption)
                Spacer()
                Button { removingTopic = key; confirmRemoval = true } label: { Image(systemName: "trash").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Dimentica associazione " + key).disabled(store.locked)
            }
        }
    }
}
