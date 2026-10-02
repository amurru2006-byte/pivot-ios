import SwiftUI

struct IncomeView: View {
    @EnvironmentObject var store: PivotStore
    @State private var addingClient = false
    @State private var addingLesson = false
    var monthPayments: [Payment] {
        let interval = PivotDate.calendar.dateInterval(of: .month, for: Date())!
        return store.data.payments.filter { $0.date >= interval.start && $0.date < interval.end }.sorted { $0.date > $1.date }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Incassato questo mese").foregroundStyle(.secondary)
                        Text(Money.display(monthPayments.reduce(0) { $0 + $1.amountCents })).font(.largeTitle.bold()).foregroundStyle(.mint)
                        Text("Da incassare: \(Money.display(store.data.income.reduce(0) { $0 + $1.outstandingCents }))")
                    }.padding(.vertical)
                    Button("Registra una lezione") { addingLesson = true }.disabled(store.data.clients.isEmpty || store.locked)
                }
                Section("Movimenti") {
                    if monthPayments.isEmpty { Text("Nessuna entrata registrata questo mese.").foregroundStyle(.secondary) }
                    ForEach(monthPayments) { payment in
                        HStack {
                            VStack(alignment: .leading) { Text(payment.clientName); Text(PivotDate.key(payment.date)).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Text("+ \(Money.display(payment.amountCents))").foregroundStyle(.mint)
                        }
                    }
                }
                Section("Da pagare") {
                    ForEach(store.data.income.filter { $0.outstandingCents > 0 }.sorted { $0.date < $1.date }) { entry in
                        NavigationLink { IncomeDetailView(entryID: entry.id) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.clientName)
                                Text("\(PivotDate.key(entry.date)) · \(entry.minutes) min · mancano \(Money.display(entry.outstandingCents))").font(.caption)
                            }
                        }
                    }
                }
                Section("Studenti") {
                    ForEach(store.data.clients) { client in
                        NavigationLink { ClientDetailView(client: client) } label: {
                            HStack { Text(client.name); Spacer(); Text("\(Money.display(client.rateCents))/h").foregroundStyle(.secondary) }
                        }
                    }
                    Button("Aggiungi studente") { addingClient = true }.disabled(store.locked)
                }
                Section { Text("Le entrate si registrano manualmente. Pivot non legge il conto bancario e non invia messaggi ai clienti.").font(.caption).foregroundStyle(.secondary) }
            }.navigationTitle("Entrate")
            .sheet(isPresented: $addingClient) { ClientForm() }
            .sheet(isPresented: $addingLesson) { LessonForm(clients: store.data.clients) }
        }
    }
}

struct ClientForm: View {
    @EnvironmentObject var store: PivotStore
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var rate = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome studente", text: $name)
                TextField("Tariffa oraria in euro", text: $rate).keyboardType(.decimalPad)
                Button("Salva") {
                    guard let cents = Money.cents(from: rate), cents > 0 else { return }
                    let client = Client(name: name.trimmingCharacters(in: .whitespacesAndNewlines), rateCents: cents)
                    if store.change({ $0.clients.append(client) }) { dismiss() }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (Money.cents(from: rate) ?? 0) <= 0)
            }.navigationTitle("Nuovo studente")
                .toolbar { Button("Annulla") { dismiss() } }
        }
    }
}

struct LessonForm: View {
    @EnvironmentObject var store: PivotStore
    @Environment(\.dismiss) var dismiss
    let clients: [Client]
    @State private var clientID: UUID
    @State private var date = Date()
    @State private var minutes = 60
    @State private var amount = ""
    @State private var alreadyPaid = false
    @State private var notes = ""
    init(clients: [Client]) { self.clients = clients; _clientID = State(initialValue: clients.first?.id ?? UUID()) }
    var selected: Client? { clients.first { $0.id == clientID } }
    var calculated: Int { Money.lessonAmount(rateCents: selected?.rateCents ?? 0, minutes: minutes) }
    var finalAmount: Int? { amount.isEmpty ? calculated : Money.cents(from: amount) }
    var body: some View {
        NavigationStack {
            Form {
                Picker("Studente", selection: $clientID) { ForEach(clients) { Text($0.name).tag($0.id) } }
                DatePicker("Data della lezione", selection: $date)
                Stepper("Durata: \(minutes) min", value: $minutes, in: 5...480, step: 5)
                Text("Importo calcolato: \(Money.display(calculated))")
                TextField("Importo diverso (facoltativo)", text: $amount).keyboardType(.decimalPad)
                Toggle("Già pagata", isOn: $alreadyPaid)
                TextField("Note", text: $notes, axis: .vertical)
                Button("Registra") {
                    guard let client = selected, let cents = finalAmount, cents > 0 else { return }
                    let entry = IncomeEntry(clientID: client.id, clientName: client.name, date: date, minutes: minutes, amountCents: cents, paidCents: alreadyPaid ? cents : 0, notes: notes)
                    if store.change({ data in
                        data.income.append(entry)
                        if alreadyPaid { data.payments.append(.init(incomeID: entry.id, clientName: client.name, date: Date(), amountCents: cents)) }
                    }) { dismiss() }
                }.disabled((finalAmount ?? 0) <= 0 || selected == nil)
            }.navigationTitle("Registra lezione")
                .toolbar { Button("Annulla") { dismiss() } }
        }
    }
}

struct IncomeDetailView: View {
    @EnvironmentObject var store: PivotStore
    let entryID: UUID
    @State private var payment = ""
    @State private var paymentDate = Date()
    @State private var message: String?
    var entry: IncomeEntry? { store.data.income.first { $0.id == entryID } }
    var body: some View {
        Form {
            if let entry {
                Section("Lezione") {
                    Text(entry.clientName).font(.headline)
                    Text("\(PivotDate.key(entry.date)) · \(entry.minutes) min")
                    Text("Totale: \(Money.display(entry.amountCents))")
                    Text("Pagato: \(Money.display(entry.paidCents))")
                    Text("Da pagare: \(Money.display(entry.outstandingCents))").foregroundStyle(.orange)
                    if !entry.notes.isEmpty { Text(entry.notes) }
                }
                if entry.outstandingCents > 0 {
                    Section("Registra incasso") {
                        DatePicker("Data pagamento", selection: $paymentDate)
                        TextField("Importo ricevuto in euro", text: $payment).keyboardType(.decimalPad)
                        Button("Registra importo") { collect(entry, cents: Money.cents(from: payment) ?? 0) }
                        Button("Registra il saldo completo") { collect(entry, cents: entry.outstandingCents) }
                    }
                }
                Section("Pagamenti ricevuti") {
                    ForEach(store.data.payments.filter { $0.incomeID == entry.id }) { p in
                        Text("\(PivotDate.key(p.date)) · \(Money.display(p.amountCents))")
                    }
                }
            }
            if let message { Text(message).foregroundStyle(.orange) }
        }.navigationTitle("Dettaglio pagamento")
    }
    private func collect(_ entry: IncomeEntry, cents: Int) {
        guard cents > 0 && cents <= entry.outstandingCents else { message = "Inserisci un importo positivo, non superiore al saldo mancante."; return }
        store.change { data in
            guard let index = data.income.firstIndex(where: { $0.id == entry.id }) else { return }
            data.income[index].paidCents += cents
            data.payments.append(.init(incomeID: entry.id, clientName: entry.clientName, date: paymentDate, amountCents: cents))
        }
        payment = ""
    }
}

struct ClientDetailView: View {
    @EnvironmentObject var store: PivotStore
    let client: Client
    var body: some View {
        List {
            ForEach(store.data.income.filter { $0.clientID == client.id }.sorted { $0.date > $1.date }) { entry in
                NavigationLink { IncomeDetailView(entryID: entry.id) } label: {
                    VStack(alignment: .leading) {
                        Text("\(PivotDate.key(entry.date)) · \(entry.minutes) minuti")
                        Text(entry.outstandingCents == 0 ? "Pagata · \(Money.display(entry.amountCents))" : "Da pagare · \(Money.display(entry.outstandingCents))").font(.caption)
                    }
                }
            }
        }.navigationTitle(client.name)
    }
}
