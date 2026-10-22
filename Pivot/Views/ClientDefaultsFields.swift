import SwiftUI

struct ClientDefaultsFields: View {
    @Binding var defaults: ClientDefaults
    @State private var choosingDestination = false
    @State private var choosingOrigin = false
    @State private var problem: String?
    var body: some View {
        DisclosureGroup("Predefiniti e tragitti") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Pagamento") {
                    Picker("Metodo di pagamento abituale", selection: $defaults.paymentMethod) {
                        ForEach(ClientPaymentMethod.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.labelsHidden().accessibilityIdentifier("client-default-payment")
                }
                LabeledContent("Luogo") {
                    Picker("Luogo abituale", selection: $defaults.place) {
                        ForEach(LessonPlace.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.labelsHidden()
                }
                TextField("Luogo / indirizzo abituale", text: $defaults.address)
                    .accessibilityIdentifier("client-default-destination")
                Button { choosingDestination = true } label: { Label("Scegli indirizzo salvato", systemImage: "bookmark") }
                    .frame(minHeight: 44).accessibilityIdentifier("client-default-saved-destination")
                ForEach($defaults.origins) { $origin in
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Partenza, es. Casa o Università", text: $origin.name)
                            .accessibilityIdentifier("client-origin-name-\(origin.id)")
                        TextField("Indirizzo di partenza (facoltativo)", text: $origin.address)
                        LabeledContent("Mezzo") {
                            Picker("Mezzo", selection: $origin.mode) {
                                ForEach(ClientTravelMode.allCases, id: \.self) { Text($0.label).tag($0) }
                            }.labelsHidden()
                        }
                        DurationField(title: "Viaggio per arrivare", seconds: Binding(get: { origin.beforeMinutes * 60 }, set: { origin.beforeMinutes = ($0 ?? 0) / 60 }), maxHours: 4)
                        DurationField(title: "Viaggio dopo l’attività", seconds: Binding(get: { origin.afterMinutes * 60 }, set: { origin.afterMinutes = ($0 ?? 0) / 60 }), maxHours: 4)
                        Button("Rimuovi partenza", role: .destructive) { defaults.origins.removeAll { $0.id == origin.id } }
                            .frame(minHeight: 44)
                    }.padding(12).background(PivotTheme.raised, in: RoundedRectangle(cornerRadius: 12))
                }
                Button { defaults.origins.append(ClientTravelOrigin()) } label: {
                    Label("Aggiungi partenza", systemImage: "plus.circle")
                }.frame(minHeight: 44).disabled(defaults.origins.count >= 12)
                    .accessibilityIdentifier("client-origin-add")
                Button { choosingOrigin = true } label: { Label("Aggiungi dai luoghi salvati", systemImage: "bookmark") }
                    .frame(minHeight: 44).disabled(defaults.origins.count >= 12).accessibilityIdentifier("client-origin-saved")
                Text("Sono proposte: nella singola attività scegli da dove parti e confermi i tempi. Puoi usare anche una partenza diversa.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
                if !defaults.isValid {
                    Text("Dai un nome diverso a ogni partenza e controlla gli indirizzi (massimo 500 caratteri).")
                        .font(.caption).foregroundStyle(PivotTheme.amber)
                }
                if let problem { Text(problem).font(.caption).foregroundStyle(PivotTheme.amber) }
            }.padding(.top, 8)
        }
        .sheet(isPresented: $choosingDestination) {
            NavigationStack { SavedPlacesView { place in
                guard place.address.count <= 500 else { problem = "L’indirizzo deve rientrare nei 500 caratteri del contatto. Non è stato troncato."; return }
                defaults.address = place.address; problem = nil
            } }
        }
        .sheet(isPresented: $choosingOrigin) {
            NavigationStack { SavedPlacesView { place in
                var next = defaults
                next.origins.append(ClientTravelOrigin(name: place.name, address: place.address))
                guard next.isValid else { problem = "Usa un nome diverso per ogni partenza, entro 120 caratteri, e un indirizzo entro 500."; return }
                defaults = next; problem = nil
            } }
        }
    }
}
