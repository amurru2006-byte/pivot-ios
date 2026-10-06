import SwiftUI

struct PaymentTermsFields: View {
    @Binding var timing: PaymentTiming
    @Binding var promisedDate: Date
    @Binding var remember: Bool
    var studentName: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Quando ti paga?", selection: $timing) {
                ForEach(PaymentTiming.allCases, id: \.self) { Text($0.label).tag($0) }
            }.accessibilityIdentifier("payment-timing")
            if timing == .chosenDate { DatePicker("Ricordamelo il", selection: $promisedDate).accessibilityIdentifier("payment-promised-date") }
            if timing.cadence != nil {
                Picker("Vale per", selection: $remember) {
                    Text("Solo questa volta").tag(false)
                    Text("Sempre per questo studente").tag(true)
                }.pickerStyle(.segmented).accessibilityIdentifier("payment-scope")
                if remember { Text("Ricorderò questa abitudine per \(studentName.isEmpty ? "lo studente" : studentName), anche nelle prossime lezioni.").font(.caption) }
            } else {
                Text("Questo rinvio vale solo per questa lezione: non cambia l’abitudine dello studente.").font(.caption)
            }
            if timing == .weekly {
                Text("Il pagamento è previsto all’ultima lezione di questa settimana nel calendario, da lunedì a domenica. Prima non ti segnalo un ritardo. Se non trovo lezioni, aggiorna il calendario o scegli una data: non invento una scadenza.").font(.caption)
            } else if timing == .nextLesson {
                Text("Ti ricorderò il saldo alla prossima lezione dello stesso studente. Se non è ancora nel calendario, scegli una data per avere subito un promemoria.").font(.caption)
            }
            Text("Nessun pagamento viene registrato finché non confermi i soldi realmente ricevuti.").font(.caption)
        }.foregroundStyle(PivotTheme.muted)
    }
}

struct PaymentDueLabel: View {
    var due: PaymentDue?
    var body: some View {
        if let due {
            if let date = due.date {
                Label((due.isOverdue(at: Date()) ? "Saldo da ricordare: " : "Pagamento previsto: ") + DisplayDate.label(date, format: "EEE d MMM · HH:mm"), systemImage: due.isOverdue(at: Date()) ? "bell.badge" : "calendar")
                    .font(.caption).foregroundStyle(due.isOverdue(at: Date()) ? PivotTheme.amber : PivotTheme.muted)
            } else {
                Text(due.timing == .weekly ? "Ultima lezione non trovata: aggiorna il calendario o scegli una data." : "In attesa della prossima lezione nel calendario; puoi scegliere una data.").font(.caption).foregroundStyle(PivotTheme.muted)
            }
        }
    }
}

struct StudentBalancePaymentView: View {
    @EnvironmentObject var store: PivotStore
    var clientID: UUID
    var clientName: String
    @State private var amount = ""
    @State private var date = Date()
    @State private var message: String?
    private var balance: Int { StudentPayments.balance(clientID: clientID, data: store.data) }
    var body: some View {
        PivotCard(tint: PivotTheme.accent) {
            Text("Un pagamento per più lezioni").font(.headline)
            Text("Saldo totale di \(clientName): \(Money.display(balance))").font(.subheadline)
            DatePicker("Ricevuto il", selection: $date)
            TextField("Quanto hai ricevuto davvero, in euro?", text: $amount).keyboardType(.decimalPad).accessibilityIdentifier("student-balance-amount")
            Text("L’importo verrà distribuito sulle lezioni non pagate, dalla più vecchia. Un pagamento parziale lascia il resto da incassare.").font(.caption).foregroundStyle(PivotTheme.muted)
            Button("Registra importo ricevuto") { collect(Money.cents(from: amount) ?? 0) }.buttonStyle(PivotPrimaryButton()).disabled(store.locked || (Money.cents(from: amount) ?? 0) <= 0)
            Button("Ho ricevuto tutto il saldo: \(Money.display(balance))") { collect(balance) }.buttonStyle(PivotSecondaryButton()).disabled(store.locked || balance == 0)
            if let message { Text(message).font(.caption).foregroundStyle(PivotTheme.amber) }
        }
    }
    private func collect(_ cents: Int) {
        guard cents > 0, cents <= balance else { message = "Inserisci un importo positivo entro il saldo. Un anticipo superiore al dovuto non viene registrato come compenso già guadagnato."; return }
        if store.change({ data in _ = StudentPayments.collect(clientID: clientID, cents: cents, date: date, data: &data) }) {
            amount = ""; message = "Pagamento registrato. Il resto, se presente, rimane da incassare."
        }
    }
}
