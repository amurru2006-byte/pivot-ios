import SwiftUI

struct IncomeView: View {
    @EnvironmentObject var store: PivotStore
    @State private var addingClient = false
    @State private var addingLesson = false
    var monthPayments: [Payment] {
        let interval = PivotDate.calendar.dateInterval(of: .month, for: Date())!
        return store.data.payments.filter { $0.date >= interval.start && $0.date < interval.end }.sorted { $0.date > $1.date }
    }
    var outstanding: [IncomeEntry] { store.data.income.filter { $0.outstandingCents > 0 }.sorted { $0.date < $1.date } }
    var body: some View {
        NavigationStack {
            PivotScreen {
                PivotHeader(title: "Le tue entrate", subtitle: "Ripetizioni, incassi e pagamenti da ricordare.")
                balance
                if store.data.clients.isEmpty {
                    PivotCard {
                        ActionRow(title: "Parti dal primo studente", subtitle: "Imposta la tariffa e registra le lezioni.", icon: "person.badge.plus")
                        Button("Aggiungi studente") { addingClient = true }.buttonStyle(PivotPrimaryButton()).disabled(store.locked)
                    }
                } else {
                    Button { addingLesson = true } label: { Label("Registra una lezione", systemImage: "plus.circle.fill") }.buttonStyle(PivotPrimaryButton()).disabled(store.locked)
                }
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "Ultimi incassi", detail: DisplayDate.label(Date(), format: "MMMM").capitalized)
                    if monthPayments.isEmpty { EmptyCard(title: "I tuoi incassi, tutti qui", message: "Quando registri un pagamento, lo ritrovi in questa lista.", icon: "eurosign.arrow.circlepath") }
                    else {
                        PivotCard {
                            ForEach(monthPayments) { payment in
                                HStack(spacing: 12) {
                                    avatar(payment.clientName)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(payment.clientName).font(.subheadline.weight(.semibold))
                                        Text(DisplayDate.label(payment.date, format: "d MMM · HH:mm")).font(.caption).foregroundStyle(PivotTheme.muted)
                                    }
                                    Spacer()
                                    Text("+ \(Money.display(payment.amountCents))").font(.subheadline.weight(.semibold)).foregroundStyle(PivotTheme.accent)
                                }
                                if payment.id != monthPayments.last?.id { Divider().overlay(.white.opacity(0.05)) }
                            }
                        }
                    }
                }
                if !outstanding.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeading(title: "Da incassare", detail: "\(outstanding.count) lezioni")
                        ForEach(outstanding) { entry in
                            NavigationLink { IncomeDetailView(entryID: entry.id) } label: {
                                PivotCard(tint: PivotTheme.amber) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(entry.clientName).font(.headline).foregroundStyle(PivotTheme.text)
                                            Text("\(DisplayDate.label(entry.date, format: "d MMM")) · \(entry.minutes) min").font(.caption).foregroundStyle(PivotTheme.muted)
                                        }
                                        Spacer()
                                        Text(Money.display(entry.outstandingCents)).font(.headline).foregroundStyle(PivotTheme.amber)
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(PivotTheme.muted)
                                    }
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "I tuoi studenti", detail: "\(store.data.clients.count)")
                    ForEach(store.data.clients) { client in
                        NavigationLink { ClientDetailView(client: client) } label: {
                            PivotCard {
                                HStack(spacing: 12) {
                                    avatar(client.name)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(client.name).font(.headline).foregroundStyle(PivotTheme.text)
                                        Text("\(Money.display(client.rateCents)) all'ora").font(.caption).foregroundStyle(PivotTheme.muted)
                                    }
                                    Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(PivotTheme.muted)
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                    if !store.data.clients.isEmpty { Button { addingClient = true } label: { Label("Aggiungi studente", systemImage: "person.badge.plus") }.buttonStyle(PivotSecondaryButton()).disabled(store.locked) }
                }
                Text("Registra qui le lezioni e gli incassi: il totale segue la data effettiva dei pagamenti.").font(.caption).foregroundStyle(PivotTheme.muted)
            }.navigationTitle("Entrate")
                .sheet(isPresented: $addingClient) { ClientForm() }
                .sheet(isPresented: $addingLesson) { LessonForm(clients: store.data.clients) }
        }
    }
    private var balance: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("Incassato questo mese", systemImage: "eurosign.circle.fill").font(.subheadline)
                Spacer(); Image(systemName: "chart.line.uptrend.xyaxis").font(.title2)
            }.foregroundStyle(PivotTheme.accent)
            Text(Money.display(monthPayments.reduce(0) { $0 + $1.amountCents })).font(.system(size: 42, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
            HStack {
                Text(DisplayDate.label(Date(), format: "MMMM yyyy").capitalized).font(.caption).foregroundStyle(PivotTheme.muted)
                Spacer()
                Text("Da incassare \(Money.display(outstanding.reduce(0) { $0 + $1.outstandingCents }))").font(.caption.weight(.semibold)).foregroundStyle(PivotTheme.amber)
            }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color(pivotHex: "22493F"), Color(pivotHex: "1C2C41"), PivotTheme.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(PivotTheme.accent.opacity(0.18)))
    }
    private func avatar(_ name: String) -> some View {
        Text(String(name.prefix(1)).uppercased()).font(.system(.headline, design: .rounded)).foregroundStyle(PivotTheme.blue)
            .frame(width: 42, height: 42).background(PivotTheme.blue.opacity(0.1), in: Circle())
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
            }.pivotForm().navigationTitle("Nuovo studente")
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
            }.pivotForm().navigationTitle("Registra lezione")
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
        }.pivotForm().navigationTitle("Dettaglio pagamento")
    }
    private func collect(_ entry: IncomeEntry, cents: Int) {
        guard cents > 0 && cents <= entry.outstandingCents else { message = "Inserisci un importo positivo, non superiore al saldo mancante."; return }
        if store.change({ data in
            guard let index = data.income.firstIndex(where: { $0.id == entry.id }) else { return }
            data.income[index].paidCents += cents
            data.payments.append(.init(incomeID: entry.id, clientName: entry.clientName, date: paymentDate, amountCents: cents))
        }) { payment = ""; message = "Pagamento registrato." }
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
        }.pivotForm().navigationTitle(client.name)
    }
}
