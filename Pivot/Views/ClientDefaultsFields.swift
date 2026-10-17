import SwiftUI

struct ClientDefaultsFields: View {
    @Binding var defaults: ClientDefaults
    var body: some View {
        DisclosureGroup("Predefiniti e tragitti") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Metodo di pagamento abituale", selection: $defaults.paymentMethod) {
                    ForEach(ClientPaymentMethod.allCases, id: \.self) { Text($0.label).tag($0) }
                }.accessibilityIdentifier("client-default-payment")
                Picker("Luogo abituale", selection: $defaults.place) {
                    ForEach(LessonPlace.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                TextField("Luogo / indirizzo abituale", text: $defaults.address)
                    .accessibilityIdentifier("client-default-destination")
                ForEach($defaults.origins) { $origin in
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Partenza, es. Casa o Università", text: $origin.name)
                            .accessibilityIdentifier("client-origin-name-\(origin.id)")
                        TextField("Indirizzo di partenza (facoltativo)", text: $origin.address)
                        Picker("Mezzo", selection: $origin.mode) {
                            ForEach(ClientTravelMode.allCases, id: \.self) { Text($0.label).tag($0) }
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
                Text("Sono proposte: nella singola attività scegli da dove parti e confermi i tempi. Puoi usare anche una partenza diversa.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
                if !defaults.isValid {
                    Text("Dai un nome diverso a ogni partenza e controlla gli indirizzi (massimo 500 caratteri).")
                        .font(.caption).foregroundStyle(PivotTheme.amber)
                }
            }.padding(.top, 8)
        }
    }
}
