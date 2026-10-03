import SwiftUI

struct CardioFields: View {
    @Binding var value: CardioRecord?
    let title: String
    var body: some View {
        PivotCard(tint: PivotTheme.blue) {
            Label("Cardio · dati allenamento", systemImage: "figure.walk").font(.headline).foregroundStyle(PivotTheme.blue)
            Picker("Tipo di attività", selection: Binding(get: { value?.kind.rawValue ?? "none" }, set: { text in
                if let kind = CardioKind(rawValue: text) { var next = value ?? CardioRecord(kind: kind); next.kind = kind; value = next }
                else { value = nil }
            })) {
                Text("Non è cardio / non indicato").tag("none")
                ForEach(CardioKind.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
            }
            if value != nil {
                Text("Inserisci solo i valori che leggi sull'Apple Watch o sulla macchina. Nessun dato è obbligatorio.").font(.caption).foregroundStyle(PivotTheme.muted)
                DurationField(title: "Durata allenamento", seconds: binding(\.durationSeconds), maxHours: 48, showSeconds: true)
                DecimalField(title: "Distanza", unit: "km", value: binding(\.distanceKM))
                DecimalField(title: "Calorie attive", unit: "kcal", value: binding(\.activeCalories))
                DecimalField(title: "Calorie totali", unit: "kcal", value: binding(\.totalCalories))
                IntegerField(title: "Battito medio (bpm)", value: binding(\.averageBPM))
                IntegerField(title: "Sforzo Apple Watch (1–10)", value: binding(\.effort))
                if value?.kind == .treadmill {
                    DecimalField(title: "Velocità tapis roulant", unit: "km/h", value: binding(\.speedKMH))
                    DecimalField(title: "Inclinazione", unit: "%", value: binding(\.inclinePercent))
                    Text("Se la macchina usa livelli invece di percentuali, scrivi il livello nelle note senza convertirlo.").font(.caption).foregroundStyle(PivotTheme.muted)
                } else {
                    DecimalField(title: "Dislivello", unit: "m", value: binding(\.elevationM))
                    DurationField(title: "Ritmo medio per km", seconds: binding(\.paceSecondsPerKM), maxHours: 0, showSeconds: true)
                }
                TextField("Note cardio: variazioni di velocità, inclinazione…", text: binding(\.notes), axis: .vertical).lineLimit(2...5)
            }
        }.onAppear {
            if value == nil, let kind = CardioKind.suggested(title) { value = CardioRecord(kind: kind) }
        }
    }
    private func binding<T>(_ path: WritableKeyPath<CardioRecord, T>) -> Binding<T> {
        Binding(get: { (value ?? CardioRecord(kind: .walk))[keyPath: path] }, set: { new in
            var record = value ?? CardioRecord(kind: .walk); record[keyPath: path] = new; value = record
        })
    }
}
