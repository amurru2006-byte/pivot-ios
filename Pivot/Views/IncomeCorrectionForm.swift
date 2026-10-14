import SwiftUI

struct IncomeCorrectionForm: View {
    @EnvironmentObject var store: PivotStore
    @Environment(\.dismiss) private var dismiss
    let incomeID: UUID
    var paymentID: UUID? = nil
    @State private var amount = ""
    @State private var message: String?
    private var original: Int? {
        if let paymentID { return store.data.payments.first { $0.id == paymentID && $0.incomeID == incomeID }?.amountCents }
        return store.data.income.first { $0.id == incomeID }?.amountCents
    }
    var body: some View {
        NavigationStack {
            PivotScreen {
                PivotHeader(title: paymentID == nil ? "Correggi compenso" : "Correggi incasso",
                            subtitle: paymentID == nil ? "Quanto era dovuto per questa lezione? Gli incassi già ricevuti non cambiano." : "Quanto hai ricevuto davvero in questo pagamento? La data e gli altri incassi non cambiano.")
                if let original {
                    Text("Importo attuale: \(Money.display(original))")
                    TextField("Importo corretto in euro", text: $amount).keyboardType(.decimalPad).accessibilityIdentifier("income-corrected-amount")
                    Text("La correzione viene conservata nello storico. Nessun conguaglio sarà aggiunto alle prossime lezioni.").font(.caption).foregroundStyle(PivotTheme.muted)
                    if let message { Text(message).foregroundStyle(PivotTheme.amber).accessibilityIdentifier("income-correction-error") }
                    Button("Salva correzione") { save() }.buttonStyle(PivotPrimaryButton()).accessibilityIdentifier("income-correction-save").disabled(store.locked || Money.cents(from: amount) == nil)
                } else { Text("Il record non è più disponibile.") }
            }.navigationTitle("Correzione")
            .onAppear { if let original { amount = String(format: "%.2f", Double(original) / 100) } }
            .toolbar { Button("Annulla") { dismiss() } }
        }
    }
    private func save() {
        guard let cents = Money.cents(from: amount), original != nil else { return }
        var next = store.data
        do {
            if let paymentID { try IncomeEdits.receipt(paymentID: paymentID, cents: cents, data: &next) }
            else { try IncomeEdits.compensation(incomeID: incomeID, cents: cents, data: &next) }
            if store.change({ $0 = next }) { dismiss() }
        } catch IncomeEdits.Failure.belowReceived {
            message = paymentID == nil ? "Il compenso non può essere inferiore agli incassi registrati. Se l'incasso era sbagliato, correggi prima quello; un rimborso reale non è una correzione." : "L'incasso totale supererebbe il compenso della lezione. Verifica prima il compenso."
        } catch { message = "Importo non valido o record non disponibile. Nessun importo è stato modificato." }
    }
}

struct ClientMergeForm: View {
    @EnvironmentObject var store: PivotStore
    @Environment(\.dismiss) private var dismiss
    let targetID: UUID
    @State private var sourceID: UUID?
    @State private var confirmed = false
    @State private var message: String?
    private var target: Client? { store.data.clients.first { $0.id == targetID } }
    private var source: Client? { store.data.clients.first { $0.id == sourceID } }
    var body: some View {
        NavigationStack {
            PivotScreen {
                if let target {
                    PivotHeader(title: "Unisci due profili", subtitle: "Da usare solo se sono davvero la stessa persona, non due omonimi.")
                    Text("Prima di unire, conserva un backup da Impostazioni. Da questa schermata l’unione non si può annullare.").font(.caption).foregroundStyle(PivotTheme.muted)
                    Text("Conserva: \(target.name) · \(Money.display(target.rateCents))/ora").font(.headline)
                    Picker("Profilo da unire", selection: $sourceID) {
                        Text("Scegli un profilo").tag(nil as UUID?)
                        ForEach(store.data.clients.filter { $0.id != targetID }) { client in
                            Text("\(client.name) · \(Money.display(client.rateCents))/ora").tag(Optional(client.id))
                        }
                    }.accessibilityIdentifier("client-merge-source")
                    if let source {
                        let count = store.data.income.filter { $0.clientID == source.id }.count
                        Text("\(count) lezioni e i relativi incassi verranno collegati al profilo conservato. Importi, date e ID delle lezioni e degli incassi non cambiano. La tariffa futura resta \(Money.display(target.rateCents))/ora; il vecchio nome resta riconoscibile nel calendario.")
                        Toggle("Confermo che è la stessa persona", isOn: $confirmed).accessibilityIdentifier("client-merge-confirm")
                    }
                    if let message { Text(message).foregroundStyle(PivotTheme.amber) }
                    Button("Unisci senza perdere lo storico") {
                        guard confirmed, let sourceID else { return }
                        var next = store.data
                        do {
                            try ClientRegistry.merge(sourceID: sourceID, into: targetID, data: &next)
                            if store.change({ $0 = next }) { dismiss() }
                        } catch { message = "I profili sono cambiati. Nessuna unione eseguita." }
                    }.buttonStyle(PivotPrimaryButton()).accessibilityIdentifier("client-merge-save").disabled(store.locked || !confirmed || source == nil)
                }
            }.navigationTitle("Unisci profili").toolbar { Button("Annulla") { dismiss() } }
            .onChange(of: sourceID) { _, _ in confirmed = false }
        }
    }
}
