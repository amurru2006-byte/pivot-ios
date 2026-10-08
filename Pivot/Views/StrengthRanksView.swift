import SwiftUI

enum StrengthRankPresentation {
    static let count = 7
    static func name(_ level: Int) -> String {
        switch level {
        case 0: return "Schiavo della gravità"
        case 1: return "Patto col ferro"
        default: return "Rank \(level + 1)"
        }
    }
    static func emblem(_ level: Int) -> String? {
        (0...1).contains(level) ? "Rank\(level + 1)Emblem" : nil
    }
    static func kg(_ value: Double) -> String { String(format: "%.1f", locale: Locale(identifier: "it_IT"), value) + " kg" }
}

struct StrengthRankEmblem: View {
    let level: Int
    var size: CGFloat = 76
    var body: some View {
        Group {
            if let asset = StrengthRankPresentation.emblem(level) {
                Image(asset).resizable().scaledToFit().padding(3)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
            } else {
                // Reserved space; the remaining user-supplied crests are pending.
                RoundedRectangle(cornerRadius: 12).stroke(PivotTheme.muted.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .overlay(Text("\(level + 1)").font(.title2.bold()).foregroundStyle(PivotTheme.muted))
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct StrengthRanksView: View {
    @EnvironmentObject var store: PivotStore
    @State private var editingProfile = false
    var library: TrainingLibrary { store.data.training ?? .init() }
    var body: some View {
        PivotScreen {
            PivotHeader(title: "La tua forza, il tuo rank", subtitle: "Sette traguardi. Progressi stimati dai tuoi allenamenti.")
            Button { editingProfile = true } label: {
                Label(store.data.strengthProfile == nil ? "Completa il profilo" : "Età, peso e altezza", systemImage: "person.crop.circle")
            }.buttonStyle(PivotSecondaryButton()).accessibilityIdentifier("strength-profile")
            ForEach(StrengthBenchmark.allCases) { benchmark in
                PivotCard {
                    Text(benchmark.title).font(.headline)
                    if let profile = store.data.strengthProfile,
                       let maximum = StrengthRanking.bestMaximum(for: benchmark, library: library),
                       let rank = StrengthRanking.result(benchmark: benchmark, maximum: maximum, profile: profile) {
                        HStack(spacing: 14) {
                            StrengthRankEmblem(level: rank.level)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(StrengthRankPresentation.name(rank.level)).font(.title3.bold())
                                Text("Rank \(rank.level + 1) / 7 · massimale stimato \(StrengthRankPresentation.kg(maximum))").font(.subheadline)
                                Text(String(format: "%.2f × peso corporeo", locale: Locale(identifier: "it_IT"), rank.relativeStrength)).font(.caption).foregroundStyle(PivotTheme.muted)
                            }
                        }
                        if let next = rank.nextTargetKG {
                            Text("Prossima soglia: \(StrengthRankPresentation.kg(next)) di massimale stimato").font(.caption).foregroundStyle(PivotTheme.accent)
                        }
                        Text(rank.percentileFloor.map { "Fascia da P\($0) nelle norme di riferimento." } ?? "Fascia sotto P10 nelle norme di riferimento.")
                            .font(.caption).foregroundStyle(PivotTheme.muted)
                    } else {
                        Text("Da valutare").font(.title3.bold())
                        Text("Servono età tra 12 e 96 anni, peso, categoria di riferimento e una serie valida con bilanciere da 1 a 10 ripetizioni.")
                            .font(.caption).foregroundStyle(PivotTheme.muted)
                    }
                }
            }
            PivotCard {
                Text("Come viene stimato").font(.headline)
                Text("Panca piana, squat e stacco sono indicatori dei movimenti indicati, non misure universali di un intero muscolo. Le altre macchine restano senza rank.")
                Text("Massimale stimato con formula di Epley, confrontato con decili per età e categoria maschile/femminile di powerlifter agonisti. Non è un percentile della popolazione generale né un test di massimale. Le proporzioni al peso corporeo hanno limiti, soprattutto ai pesi estremi. L’altezza non entra nelle soglie pubblicate.")
                Text("I sette livelli sono una scelta motivazionale di Pivot. I nomi e gli stemmi dal terzo al settimo sono in arrivo.")
                Link("Norme pubblicate · van den Hoek et al., 2024", destination: URL(string: StrengthRanking.sourceURL)!)
            }.font(.caption)
            SectionHeading(title: "I sette rank")
            ForEach(0..<StrengthRankPresentation.count, id: \.self) { level in
                PivotCard {
                    HStack(spacing: 14) {
                        StrengthRankEmblem(level: level, size: 58)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(StrengthRankPresentation.name(level)).font(.headline)
                            Text(level < 2 ? "Rank \(level + 1) / 7" : "Spazio riservato · nome e stemma in arrivo")
                                .font(.caption).foregroundStyle(PivotTheme.muted)
                        }
                    }
                }
            }
        }.navigationTitle("Rank")
            .sheet(isPresented: $editingProfile) { StrengthProfileEditor() }
    }
}

struct StrengthProfileEditor: View {
    @EnvironmentObject var store: PivotStore
    @EnvironmentObject var health: HealthService
    @Environment(\.dismiss) private var dismiss
    @State private var profile = StrengthProfile()
    @State private var loading = false
    @State private var message: String?
    @State private var initialized = false
    @State private var wantsBirthDate = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Il tuo profilo") {
                    Toggle("Inserisci la data di nascita", isOn: Binding(get: { wantsBirthDate }, set: { enabled in
                        wantsBirthDate = enabled
                        if !enabled { profile.birthDate = nil }
                    }))
                    if wantsBirthDate {
                        DatePicker("Data di nascita", selection: Binding(get: { profile.birthDate ?? Date() }, set: { profile.birthDate = $0 }), in: ...Date(), displayedComponents: .date)
                            .accessibilityIdentifier("strength-birth-date")
                        if let age = profile.age() { Text("Età: \(age) anni").foregroundStyle(PivotTheme.muted) }
                    }
                    DecimalField(title: "Peso", unit: "kg", value: $profile.bodyMassKG, identifier: "strength-weight")
                    DecimalField(title: "Altezza", unit: "cm", value: $profile.heightCM, identifier: "strength-height")
                    Picker("Categoria delle norme", selection: $profile.referenceSex) {
                        Text("Da scegliere").tag(StrengthReferenceSex?.none)
                        ForEach(StrengthReferenceSex.allCases) { sex in Text(sex.label).tag(Optional(sex)) }
                    }
                    Text("Le tabelle pubblicate distinguono maschile e femminile. Scegli la categoria da usare per il confronto; puoi lasciare il rank non valutato.").font(.caption)
                }
                Section("Apple Salute · facoltativo") {
                    Button(loading ? "Leggo il profilo…" : "Importa età, peso e altezza") {
                        Task { await importHealth() }
                    }.disabled(loading || store.locked).accessibilityIdentifier("strength-health-import")
                    Text("I permessi vengono richiesti solo quando premi Importa. Controlla i valori prima di salvarli: Pivot legge Salute e calcola i rank sull’iPhone.").font(.caption)
                    if let date = profile.measuredAt { Text("Peso misurato il \(PivotDate.shortDate(date))").font(.caption) }
                    if let message { Text(message).font(.caption).foregroundStyle(PivotTheme.amber) }
                }
            }.navigationTitle("Profilo forza")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Salva") { save() }.disabled(loading || store.locked) }
                }
                .onAppear { if !initialized { profile = store.data.strengthProfile ?? .init(); wantsBirthDate = profile.birthDate != nil; initialized = true } }
        }
    }
    private func importHealth() async {
        loading = true; defer { loading = false }
        do {
            let imported = try await health.readStrengthProfile()
            if let date = imported.birthDate { profile.birthDate = date; wantsBirthDate = true }
            if let mass = imported.bodyMassKG { profile.bodyMassKG = mass; profile.measuredAt = imported.measuredAt }
            if let height = imported.heightCM { profile.heightCM = height }
            message = "Controlla i dati importati e la data del peso. I campi non disponibili restano da compilare: Salute può avere dati mancanti o non leggibili."
        } catch { message = error.localizedDescription }
    }
    private func save() {
        if wantsBirthDate && profile.birthDate == nil { message = "Scegli la tua data di nascita prima di salvare."; return }
        do {
            try profile.validate()
            if profile.bodyMassKG != store.data.strengthProfile?.bodyMassKG && profile.measuredAt == store.data.strengthProfile?.measuredAt {
                profile.measuredAt = profile.bodyMassKG == nil ? nil : Date()
            }
            if store.change({ $0.strengthProfile = profile }) { dismiss() }
        } catch { message = "Controlla data di nascita, peso (20–350 kg) e altezza (80–250 cm). I dati precedenti sono conservati." }
    }
}
