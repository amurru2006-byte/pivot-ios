import SwiftUI

struct IncomeView: View {
    @EnvironmentObject var store: PivotStore
    @State private var addingClient = false
    @State private var addingLesson = false
    @State private var selectedYear: Int? = nil
    @State private var exportFile: URL?
    @State private var exporting = false
    @State private var editingOpening = false
    var currentYear: Int { PivotDate.calendar.component(.year, from: Date()) }
    var year: Int { selectedYear ?? currentYear }
    var ledger: AnnualLedger { store.data.ledger ?? AnnualLedger() }
    var annualTotal: Int { ledger.total(year: year, payments: store.data.payments) }
    var years: [Int] { Array(Set([currentYear] + store.data.payments.map { PivotDate.calendar.component(.year, from: $0.date) } + ledger.openingCents.keys.compactMap(Int.init))).sorted(by: >) }
    var balanceColor: Color {
        guard let progress = ledger.warningProgress(total: annualTotal) else { return PivotTheme.accent }
        return Color(red: 1, green: 0.82 * (1 - progress) + 0.12 * progress, blue: 0.1 * (1 - progress) + 0.18 * progress)
    }
    var monthPayments: [Payment] {
        return store.data.payments.filter { PivotDate.calendar.component(.year, from: $0.date) == year }.sorted { $0.date > $1.date }
    }
    var outstanding: [IncomeEntry] { store.data.income.filter { $0.outstandingCents > 0 }.sorted { $0.date < $1.date } }
    var body: some View {
        NavigationStack {
            PivotScreen {
                PivotHeader(title: "Le tue entrate", subtitle: "Ripetizioni, incassi e pagamenti da ricordare.")
                balance
                HStack {
                    Button { editingOpening = true } label: { Label("Importo pregresso", systemImage: "slider.horizontal.3") }.buttonStyle(PivotSecondaryButton()).disabled(store.locked)
                    Button {
                        Task {
                            do { exportFile = try await store.incomeExcelURL(year: year); exporting = true }
                            catch { store.error = "Esportazione non riuscita: \(error.localizedDescription)" }
                        }
                    } label: { Label("Esporta in Excel", systemImage: "square.and.arrow.up") }.buttonStyle(PivotSecondaryButton()).disabled(store.locked)
                }
                PivotCard(tint: PivotTheme.amber) {
                    DisclosureGroup {
                        Text(AnnualLedger.fiscalExplanation).font(.caption).foregroundStyle(PivotTheme.muted).padding(.top, 8)
                        Link("Leggi la fonte INPS", destination: URL(string: AnnualLedger.sourceURL)!).font(.subheadline)
                    } label: { Label("Fiscalità: verifica anche sotto 5.000 €", systemImage: "info.circle").font(.subheadline.weight(.semibold)) }
                    Text("Se fai ripetizioni regolarmente, verifica l'inquadramento adesso: la cifra da sola non determina gli obblighi.").font(.caption).foregroundStyle(PivotTheme.muted)
                }
                if store.data.clients.isEmpty {
                    PivotCard {
                        ActionRow(title: "Parti dal primo studente", subtitle: "Imposta la tariffa e registra le lezioni.", icon: "person.badge.plus")
                        Button("Aggiungi studente") { addingClient = true }.buttonStyle(PivotPrimaryButton()).disabled(store.locked)
                    }
                } else {
                    Button { addingLesson = true } label: { Label("Registra una lezione", systemImage: "plus.circle.fill") }.buttonStyle(PivotPrimaryButton()).disabled(store.locked)
                }
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "Ultimi incassi", detail: String(year))
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
                        SectionHeading(title: "Da incassare", detail: "\(outstanding.count) \(outstanding.count == 1 ? "lezione" : "lezioni")")
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
                .sheet(isPresented: $exporting) { if let exportFile { ShareSheet(items: [exportFile]) } }
                .sheet(isPresented: $editingOpening) { OpeningIncomeForm(year: year) }
        }
    }
    private var balance: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("Incassato nell’anno", systemImage: "eurosign.circle.fill").font(.subheadline)
                Spacer()
                Picker("Anno", selection: Binding(get: { year }, set: { selectedYear = $0 == currentYear ? nil : $0 })) { ForEach(years, id: \.self) { Text(String($0)).tag($0) } }.pickerStyle(.menu)
            }.foregroundStyle(PivotTheme.accent)
            Text(Money.display(annualTotal)).foregroundStyle(balanceColor).font(.system(size: 42, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
            HStack {
                Text("1 gennaio – 31 dicembre \(year)").font(.caption).foregroundStyle(PivotTheme.muted)
                Spacer()
                Text("Da incassare \(Money.display(outstanding.reduce(0) { $0 + $1.outstandingCents }))").font(.caption.weight(.semibold)).foregroundStyle(PivotTheme.amber)
            }
            if let progress = ledger.warningProgress(total: annualTotal) {
                Label(progress >= 1 ? "Riferimento INPS raggiunto: verifica gli adempimenti" : "Ti avvicini al riferimento INPS: \(Money.display(max(0, ledger.referenceCents - annualTotal))) rimanenti", systemImage: "exclamationmark.triangle.fill").font(.caption.weight(.semibold)).foregroundStyle(balanceColor)
            }
            Text("Riferimento INPS 5.000 € · avviso da 4.500 €. Non è un limite esente da tasse. Il nuovo anno riparte da zero, senza cancellare lo storico.").font(.caption).foregroundStyle(PivotTheme.muted)
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
            PivotScreen {
                PivotHeader(title: "Nuovo studente", subtitle: "Nome e tariffa: poi sei pronto a registrare le lezioni.")
                PivotCard {
                    Label("Studente", systemImage: "person.fill").font(.headline).foregroundStyle(PivotTheme.blue)
                    TextField("Nome", text: $name).textContentType(.name).padding(14).background(PivotTheme.raised, in: RoundedRectangle(cornerRadius: 12))
                    Label("Tariffa all'ora", systemImage: "eurosign.circle").font(.subheadline.weight(.semibold))
                    HStack {
                        TextField("Ad esempio 18", text: $rate).keyboardType(.decimalPad)
                        Text("€/h").foregroundStyle(PivotTheme.muted)
                    }.padding(14).background(PivotTheme.raised, in: RoundedRectangle(cornerRadius: 12))
                }
                Button("Aggiungi studente") {
                    guard let cents = Money.cents(from: rate), cents > 0 else { return }
                    let client = Client(name: name.trimmingCharacters(in: .whitespacesAndNewlines), rateCents: cents)
                    if store.change({ $0.clients.append(client) }) { dismiss() }
                }.buttonStyle(PivotPrimaryButton()).disabled(store.locked || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (Money.cents(from: rate) ?? 0) <= 0)
            }.navigationTitle("Studente")
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
            PivotScreen {
                PivotHeader(title: "Una lezione in più", subtitle: "Registra il lavoro fatto e tieni traccia del pagamento.")
                PivotCard {
                    HStack {
                        Label("Studente", systemImage: "person.fill").font(.subheadline.weight(.semibold))
                        Spacer()
                        Picker("Studente", selection: $clientID) { ForEach(clients) { Text($0.name).tag($0.id) } }.pickerStyle(.menu).labelsHidden()
                    }
                    DatePicker("Data della lezione", selection: $date)
                    DurationField(title: "Durata della lezione", seconds: Binding(get: { minutes * 60 }, set: { minutes = max(1, ($0 ?? 60) / 60) }), maxHours: 8)
                }
                PivotCard(tint: PivotTheme.accent) {
                    Text("Importo della lezione").font(.subheadline).foregroundStyle(PivotTheme.muted)
                    Text(Money.display(finalAmount ?? 0)).font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(PivotTheme.accent)
                    Text("Calcolato dalla tariffa: \(Money.display(calculated))").font(.caption).foregroundStyle(PivotTheme.muted)
                    TextField("Importo diverso in euro, se serve", text: $amount).keyboardType(.decimalPad).padding(12).background(PivotTheme.raised, in: RoundedRectangle(cornerRadius: 12))
                    Toggle("Già pagata", isOn: $alreadyPaid)
                    if alreadyPaid { Text("L'incasso verrà registrato con la data di oggi.").font(.caption).foregroundStyle(PivotTheme.muted) }
                }
                PivotCard { TextField("Note della lezione…", text: $notes, axis: .vertical).lineLimit(3...6) }
                Button("Registra lezione") {
                    guard let client = selected, let cents = finalAmount, cents > 0 else { return }
                    let entry = IncomeEntry(clientID: client.id, clientName: client.name, date: date, minutes: minutes, amountCents: cents, paidCents: alreadyPaid ? cents : 0, notes: notes)
                    if store.change({ data in
                        data.income.append(entry)
                        if alreadyPaid { data.payments.append(.init(incomeID: entry.id, clientName: client.name, date: Date(), amountCents: cents)) }
                    }) { dismiss() }
                }.buttonStyle(PivotPrimaryButton()).disabled(store.locked || (finalAmount ?? 0) <= 0 || selected == nil)
            }.navigationTitle("Lezione")
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
        PivotScreen {
            if let entry {
                PivotHeader(title: entry.clientName, subtitle: "\(DisplayDate.label(entry.date, format: "d MMMM yyyy")) · \(entry.minutes) minuti di lezione")
                PivotCard(tint: entry.outstandingCents > 0 ? PivotTheme.amber : PivotTheme.accent) {
                    Text(entry.outstandingCents > 0 ? "Da incassare" : "Lezione saldata").font(.subheadline).foregroundStyle(PivotTheme.muted)
                    Text(Money.display(entry.outstandingCents > 0 ? entry.outstandingCents : entry.amountCents)).font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(entry.outstandingCents > 0 ? PivotTheme.amber : PivotTheme.accent)
                    HStack { Text("Totale \(Money.display(entry.amountCents))"); Spacer(); Text("Ricevuto \(Money.display(entry.paidCents))") }.font(.caption).foregroundStyle(PivotTheme.muted)
                    if !entry.notes.isEmpty { Text(entry.notes).font(.subheadline) }
                }
                if entry.outstandingCents > 0 {
                    PivotCard {
                        SectionHeading(title: "Registra un pagamento")
                        DatePicker("Data pagamento", selection: $paymentDate)
                        TextField("Importo ricevuto in euro", text: $payment).keyboardType(.decimalPad).padding(12).background(PivotTheme.raised, in: RoundedRectangle(cornerRadius: 12))
                        Button("Registra importo") { collect(entry, cents: Money.cents(from: payment) ?? 0) }.buttonStyle(PivotPrimaryButton()).disabled(store.locked || (Money.cents(from: payment) ?? 0) <= 0)
                        Button("Registra il saldo completo") { collect(entry, cents: entry.outstandingCents) }.buttonStyle(PivotSecondaryButton()).disabled(store.locked)
                    }
                }
                let payments = store.data.payments.filter { $0.incomeID == entry.id }.sorted { $0.date > $1.date }
                if !payments.isEmpty {
                    PivotCard {
                        SectionHeading(title: "Pagamenti ricevuti")
                        ForEach(payments) { p in HStack { Text(DisplayDate.label(p.date, format: "d MMM yyyy")).foregroundStyle(PivotTheme.muted); Spacer(); Text("+ \(Money.display(p.amountCents))").foregroundStyle(PivotTheme.accent) }.font(.subheadline) }
                    }
                }
            } else { EmptyCard(title: "Lezione non disponibile", message: "Torna alle entrate per scegliere una lezione.", icon: "eurosign.circle") }
            if let message { Label(message, systemImage: "info.circle").font(.subheadline).foregroundStyle(PivotTheme.amber) }
        }.navigationTitle("Pagamento")
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
    var entries: [IncomeEntry] { store.data.income.filter { $0.clientID == client.id }.sorted { $0.date > $1.date } }
    var body: some View {
        PivotScreen {
            PivotHeader(title: client.name, subtitle: "\(Money.display(client.rateCents)) all'ora · \(entries.count) lezioni registrate")
            HStack(spacing: 10) {
                MetricTile(title: "Ricevuto", value: Money.display(entries.reduce(0) { $0 + $1.paidCents }), icon: "checkmark.circle.fill")
                MetricTile(title: "Da incassare", value: Money.display(entries.reduce(0) { $0 + $1.outstandingCents }), icon: "clock.fill", color: PivotTheme.amber)
            }
            SectionHeading(title: "Le lezioni")
            if entries.isEmpty { EmptyCard(title: "Pronto per la prima lezione", message: "Registra una lezione dalla schermata Entrate.", icon: "person.2.fill") }
            ForEach(entries) { entry in
                NavigationLink { IncomeDetailView(entryID: entry.id) } label: {
                    PivotCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(DisplayDate.label(entry.date, format: "d MMM yyyy")) · \(entry.minutes) min").font(.subheadline.weight(.semibold)).foregroundStyle(PivotTheme.text)
                                Text(entry.outstandingCents == 0 ? "Pagata · \(Money.display(entry.amountCents))" : "Da incassare · \(Money.display(entry.outstandingCents))").font(.caption).foregroundStyle(entry.outstandingCents == 0 ? PivotTheme.accent : PivotTheme.amber)
                            }
                            Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(PivotTheme.muted)
                        }
                    }
                }.buttonStyle(.plain)
            }
        }.navigationTitle("Studente")
    }
}

struct OpeningIncomeForm: View {
    @EnvironmentObject var store: PivotStore
    @Environment(\.dismiss) var dismiss
    let year: Int
    @State private var total = ""
    var recorded: Int { store.data.payments.filter { PivotDate.calendar.component(.year, from: $0.date) == year }.reduce(0) { $0 + $1.amountCents } }
    var body: some View {
        NavigationStack {
            PivotScreen {
                PivotHeader(title: "Incassi già ricevuti", subtitle: "Anno \(year). Imposta il totale prima di iniziare a usare il registro.")
                PivotCard {
                    TextField("Totale già incassato in euro", text: $total).keyboardType(.decimalPad).padding(14).background(PivotTheme.raised, in: RoundedRectangle(cornerRadius: 12))
                    Text("Include i pagamenti già registrati (\(Money.display(recorded))). Li sottraggo dall'importo pregresso per evitare doppioni. Non creo ricevute o studenti fittizi.").font(.caption).foregroundStyle(PivotTheme.muted)
                }
                Button("Salva totale iniziale") {
                    guard let cents = Money.cents(from: total), cents >= recorded else { return }
                    if store.change({ data in var ledger = data.ledger ?? AnnualLedger(); ledger.setOpeningTotal(cents, year: year, payments: data.payments); data.ledger = ledger }) { dismiss() }
                }.buttonStyle(PivotPrimaryButton()).disabled(store.locked || (Money.cents(from: total) ?? -1) < recorded)
            }.navigationTitle("Importo pregresso").toolbar { Button("Annulla") { dismiss() } }
                .onAppear { total = String(Double((store.data.ledger ?? AnnualLedger()).total(year: year, payments: store.data.payments)) / 100) }
        }
    }
}
