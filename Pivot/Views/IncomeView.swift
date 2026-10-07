import SwiftUI
import Charts

private enum IncomeChartRange: String, CaseIterable, Identifiable {
    case days, months, year, years
    var id: String { rawValue }
    var label: String {
        switch self { case .days: "30 giorni"; case .months: "12 mesi"; case .year: "Anno scelto"; case .years: "Tutti gli anni" }
    }
}

private enum IncomeChartStyle: String, CaseIterable, Identifiable {
    case bars, line, area
    var id: String { rawValue }
    var label: String { switch self { case .bars: "Barre"; case .line: "Linea"; case .area: "Area" } }
}

private struct IncomeChartPoint: Identifiable {
    var id: String { key }
    var key: String
    var label: String
    var amountCents: Int
    var euros: Double { Double(amountCents) / 100 }
}

private struct IncomePageHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct IncomeView: View {
    @EnvironmentObject var store: PivotStore
    @EnvironmentObject var agenda: AgendaService
    @State private var addingClient = false
    @State private var addingLesson = false
    @State private var selectedYear: Int? = nil
    @State private var exportFile: URL?
    @State private var exporting = false
    @State private var editingOpening = false
    @State private var balancePage = 0
    @State private var carouselHeight: CGFloat = 350
    @State private var chartRange: IncomeChartRange = .year
    @State private var chartStyle: IncomeChartStyle = .bars
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
                balanceCarousel
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
                                            PaymentDueLabel(due: agenda.paymentDues.first { $0.entryIDs.contains(entry.id) })
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
                        }.buttonStyle(.plain).accessibilityIdentifier("client-detail-" + client.id.uuidString)
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
    private var balanceCarousel: some View {
        VStack(spacing: 10) {
            TabView(selection: $balancePage) {
                balance.tag(0)
                incomeChart.tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: carouselHeight)
            .onPreferenceChange(IncomePageHeight.self) { height in
                if height > 0, abs(carouselHeight - max(350, height)) > 1 {
                    carouselHeight = max(350, height)
                }
            }
            .accessibilityLabel("Riepilogo e grafico delle entrate, scorri orizzontalmente")
            .accessibilityIdentifier("income-carousel")

            // Navigation lives outside the cards: it cannot cover chart labels
            // or the explanation, even with larger accessibility text.
            HStack(spacing: 20) {
                incomePageButton("Riepilogo", page: 0)
                incomePageButton("Grafico", page: 1)
            }
        }
    }
    private func incomePageButton(_ title: String, page: Int) -> some View {
        Button { withAnimation { balancePage = page } } label: {
            HStack(spacing: 6) {
                Circle().fill(balancePage == page ? PivotTheme.accent : PivotTheme.muted).frame(width: 7, height: 7)
                Text(title).font(.caption.weight(balancePage == page ? .semibold : .regular))
            }.foregroundStyle(balancePage == page ? PivotTheme.accent : PivotTheme.muted)
                .padding(.vertical, 8)
        }.buttonStyle(.plain)
            .accessibilityAddTraits(balancePage == page ? .isSelected : [])
            .accessibilityIdentifier("income-page-\(page)")
    }
    private func measuredIncomePage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: IncomePageHeight.self, value: geometry.size.height)
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private var balance: some View {
        measuredIncomePage {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label {
                    Text("Incassato nell’anno").accessibilityIdentifier("income-summary-title")
                } icon: { Image(systemName: "eurosign.circle.fill") }.font(.subheadline)
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
        }.padding(24).frame(maxWidth: .infinity, alignment: .topLeading)
        }
            .background(LinearGradient(colors: [Color(pivotHex: "22493F"), Color(pivotHex: "1C2C41"), PivotTheme.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(PivotTheme.accent.opacity(0.18)))
    }
    private var incomeChart: some View {
        measuredIncomePage {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Andamento incassi").accessibilityIdentifier("income-chart-title")
            } icon: { Image(systemName: "chart.xyaxis.line") }
                .font(.subheadline.weight(.semibold)).foregroundStyle(PivotTheme.blue)
            Picker("Intervallo", selection: $chartRange) { ForEach(IncomeChartRange.allCases) { Text($0.label).tag($0) } }.pickerStyle(.menu)
            HStack {
                Text(chartRange == .year ? String(year) : chartRange.label).font(.caption).foregroundStyle(PivotTheme.muted)
                Spacer()
                Picker("Tipo di grafico", selection: $chartStyle) { ForEach(IncomeChartStyle.allCases) { Text($0.label).tag($0) } }.pickerStyle(.menu)
            }
            if chartPoints.allSatisfy({ $0.amountCents == 0 }) {
                ContentUnavailableView("Nessun incasso datato", systemImage: "chart.bar", description: Text("Registra un pagamento per costruire il grafico."))
            } else {
                Chart(chartPoints) { point in
                    switch chartStyle {
                    case .bars:
                        BarMark(x: .value("Periodo", point.label), y: .value("Euro", point.euros)).foregroundStyle(PivotTheme.accent.gradient)
                    case .line:
                        LineMark(x: .value("Periodo", point.label), y: .value("Euro", point.euros)).foregroundStyle(PivotTheme.blue).interpolationMethod(.catmullRom)
                        PointMark(x: .value("Periodo", point.label), y: .value("Euro", point.euros)).foregroundStyle(PivotTheme.blue)
                    case .area:
                        AreaMark(x: .value("Periodo", point.label), y: .value("Euro", point.euros)).foregroundStyle(LinearGradient(colors: [PivotTheme.blue.opacity(0.65), PivotTheme.blue.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Periodo", point.label), y: .value("Euro", point.euros)).foregroundStyle(PivotTheme.blue)
                    }
                }.chartYScale(domain: 0...max(1, (chartPoints.map(\.euros).max() ?? 0) * 1.15))
                    .chartYAxisLabel("€").frame(height: 205)
                    .accessibilityIdentifier("income-chart-plot")
            }
            Text(chartRange == .years ? "La vista annuale comprende anche gli importi pregressi." : "Giorni e mesi mostrano soltanto pagamenti con una data; l'importo pregresso resta nel totale annuale.")
                .font(.caption2).foregroundStyle(PivotTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("income-chart-explanation")
        }.padding(20).frame(maxWidth: .infinity, alignment: .topLeading)
        }
            .background(PivotTheme.surface, in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(PivotTheme.blue.opacity(0.2)))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("income-chart")
    }
    private var chartPoints: [IncomeChartPoint] {
        let calendar = PivotDate.calendar
        switch chartRange {
        case .days:
            let today = calendar.startOfDay(for: Date())
            return (0..<30).reversed().compactMap { offset -> IncomeChartPoint? in
                guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
                let next = calendar.date(byAdding: .day, value: 1, to: date)!
                let cents = store.data.payments.filter { $0.date >= date && $0.date < next }.reduce(0) { $0 + $1.amountCents }
                return IncomeChartPoint(key: PivotDate.key(date), label: DisplayDate.label(date, format: "d/M"), amountCents: cents)
            }
        case .months:
            let now = Date(), components = calendar.dateComponents([.year, .month], from: now)
            guard let currentMonth = calendar.date(from: components) else { return [] }
            return (0..<12).reversed().compactMap { offset -> IncomeChartPoint? in
                guard let date = calendar.date(byAdding: .month, value: -offset, to: currentMonth), let next = calendar.date(byAdding: .month, value: 1, to: date) else { return nil }
                let cents = store.data.payments.filter { $0.date >= date && $0.date < next }.reduce(0) { $0 + $1.amountCents }
                return IncomeChartPoint(key: DisplayDate.label(date, format: "yyyy-MM"), label: DisplayDate.label(date, format: "MMM yy"), amountCents: cents)
            }
        case .year:
            return (1...12).compactMap { month -> IncomeChartPoint? in
                guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)), let next = calendar.date(byAdding: .month, value: 1, to: date) else { return nil }
                let cents = store.data.payments.filter { $0.date >= date && $0.date < next }.reduce(0) { $0 + $1.amountCents }
                return IncomeChartPoint(key: "\(year)-\(month)", label: DisplayDate.label(date, format: "MMM"), amountCents: cents)
            }
        case .years:
            return years.reversed().map { value in IncomeChartPoint(key: String(value), label: String(value), amountCents: ledger.total(year: value, payments: store.data.payments)) }
        }
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
    @State private var cadence: PaymentCadence = .everyLesson
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
                    Picker("Come ti paga di solito?", selection: $cadence) {
                        ForEach(PaymentCadence.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
                Button("Aggiungi studente") {
                    guard let cents = Money.cents(from: rate), cents > 0 else { return }
                    let client = Client(name: name.trimmingCharacters(in: .whitespacesAndNewlines), rateCents: cents, paymentCadence: cadence)
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
    @State private var paymentTiming: PaymentTiming = .everyLesson
    @State private var promisedDate = Date()
    @State private var rememberCadence = false
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
                    if !alreadyPaid { PaymentTermsFields(timing: $paymentTiming, promisedDate: $promisedDate, remember: $rememberCadence, studentName: selected?.name ?? "") }
                }
                PivotCard { TextField("Note della lezione…", text: $notes, axis: .vertical).lineLimit(3...6) }
                Button("Registra lezione") {
                    guard let client = selected, let cents = finalAmount, cents > 0 else { return }
                    let entry = IncomeEntry(clientID: client.id, clientName: client.name, date: date, minutes: minutes, amountCents: cents, paidCents: alreadyPaid ? cents : 0, notes: notes, paymentTiming: paymentTiming, promisedPaymentDate: paymentTiming == .chosenDate ? promisedDate : nil)
                    if store.change({ data in
                        data.income.append(entry)
                        if rememberCadence { StudentPayments.remember(paymentTiming, for: client.id, data: &data) }
                        if alreadyPaid { data.payments.append(.init(incomeID: entry.id, clientName: client.name, date: Date(), amountCents: cents)) }
                    }) { dismiss() }
                }.buttonStyle(PivotPrimaryButton()).disabled(store.locked || (finalAmount ?? 0) <= 0 || selected == nil)
            }.navigationTitle("Lezione")
                .onAppear { paymentTiming = store.data.clients.first { $0.id == clientID }?.paymentCadence?.timing ?? .everyLesson }
                .onChange(of: clientID) { _, id in paymentTiming = store.data.clients.first { $0.id == id }?.paymentCadence?.timing ?? .everyLesson; rememberCadence = false }
                .toolbar { Button("Annulla") { dismiss() } }
        }
    }
}

struct IncomeDetailView: View {
    @EnvironmentObject var store: PivotStore
    @EnvironmentObject var agenda: AgendaService
    let entryID: UUID
    @State private var payment = ""
    @State private var paymentDate = Date()
    @State private var message: String?
    @State private var timing: PaymentTiming = .everyLesson
    @State private var promisedDate = Date()
    @State private var rememberCadence = false
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
                    PaymentDueLabel(due: agenda.paymentDues.first { $0.entryIDs.contains(entry.id) })
                }
                if entry.outstandingCents > 0 {
                    PivotCard {
                        Text("Quando riceverai il resto?").font(.headline)
                        PaymentTermsFields(timing: $timing, promisedDate: $promisedDate, remember: $rememberCadence, studentName: entry.clientName)
                        Button("Salva promemoria") {
                            store.change { data in
                                guard let index = data.income.firstIndex(where: { $0.id == entryID }) else { return }
                                data.income[index].paymentTiming = timing
                                data.income[index].promisedPaymentDate = timing == .chosenDate ? promisedDate : nil
                                data.income[index].paymentDeferralAfter = timing == .nextLesson ? max(Date(), entry.date) : nil
                                data.income[index].lastKnownPaymentDate = nil
                                if rememberCadence { StudentPayments.remember(timing, for: entry.clientID, data: &data) }
                            }
                            message = "Scadenza aggiornata. Nessun incasso è stato aggiunto."
                        }.buttonStyle(PivotSecondaryButton()).disabled(store.locked)
                    }
                    PivotCard {
                        SectionHeading(title: "Registra un pagamento")
                        DatePicker("Data pagamento", selection: $paymentDate)
                        TextField("Importo ricevuto in euro", text: $payment).keyboardType(.decimalPad).padding(12).background(PivotTheme.raised, in: RoundedRe…1186 tokens truncated…otCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(DisplayDate.label(entry.date, format: "d MMM yyyy")) · \(entry.minutes) min").font(.subheadline.weight(.semibold)).foregroundStyle(PivotTheme.text)
                                Text(entry.outstandingCents == 0 ? "Pagata · \(Money.display(entry.amountCents))" : "Da incassare · \(Money.display(entry.outstandingCents))").font(.caption).foregroundStyle(entry.outstandingCents == 0 ? PivotTheme.accent : PivotTheme.amber)
                                if entry.outstandingCents > 0 { PaymentDueLabel(due: agenda.paymentDues.first { $0.entryIDs.contains(entry.id) }) }
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
