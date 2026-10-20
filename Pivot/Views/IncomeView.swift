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

struct IncomeView: View {
    @EnvironmentObject var store: PivotStore
    @EnvironmentObject var agenda: AgendaService
    @EnvironmentObject var calendar: CalendarService
    @State private var addingClient = false
    @State private var addingLesson = false
    @State private var importingHistory = false
    @State private var selectedYear: Int? = nil
    @State private var exportFile: URL?
    @State private var exporting = false
    @State private var editingOpening = false
    @State private var balancePage = 0
    @State private var carouselHeights: [Int: CGFloat] = [:]
    @State private var chartRange: IncomeChartRange = .year
    @State private var chartStyle: IncomeChartStyle = .bars
    @State private var selectedBar: String?
    @State private var showAllReceipts = false
    @State private var showInactiveContacts = false
    @State private var orderedContactIDs: [UUID] = []
    private var orderedContacts: [Client] {
        let ranks = Dictionary(orderedContactIDs.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return store.data.clients.sorted { ranks[$0.id, default: Int.max] < ranks[$1.id, default: Int.max] }
    }
    private var visibleReceipts: [Payment] { showAllReceipts ? monthPayments : Array(monthPayments.prefix(5)) }
    var currentYear: Int { PivotDate.calendar.component(.year, from: Date()) }
    var year: Int { selectedYear ?? currentYear }
    var ledger: AnnualLedger { store.data.ledger ?? AnnualLedger() }
    var annualTotal: Int { ledger.total(year: year, payments: store.data.payments) }
    var years: [Int] { Array(Set([currentYear] + store.data.payments.compactMap(\.year) + ledger.openingCents.keys.compactMap(Int.init))).sorted(by: >) }
    var balanceColor: Color {
        guard let progress = ledger.warningProgress(total: annualTotal) else { return PivotTheme.accent }
        return Color(red: 1, green: 0.82 * (1 - progress) + 0.12 * progress, blue: 0.1 * (1 - progress) + 0.18 * progress)
    }
    var monthPayments: [Payment] {
        return store.data.payments.filter { $0.year == year }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
    var outstanding: [IncomeEntry] { store.data.income.filter { $0.outstandingCents > 0 }.sorted { $0.date < $1.date } }
    private var carouselHeight: CGFloat {
        // Fallback only until measurement: no permanent padding to a taller page.
        carouselHeights[balancePage] ?? (balancePage == 1 ? 360 : 280)
    }
    var body: some View {
        NavigationStack {
            PivotScreen {
                PivotHeader(title: "Le tue entrate", subtitle: "Attività, incassi e pagamenti da ricordare.")
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
                Button { importingHistory = true } label: { Label("Recupera dal calendario", systemImage: "calendar.badge.clock") }
                    .buttonStyle(PivotSecondaryButton()).disabled(store.locked).accessibilityIdentifier("income-history-open")
                PivotCard(tint: PivotTheme.amber) {
                    DisclosureGroup {
                        Text(AnnualLedger.fiscalExplanation).font(.caption).foregroundStyle(PivotTheme.muted).padding(.top, 8)
                        Link("Leggi la fonte INPS", destination: URL(string: AnnualLedger.sourceURL)!).font(.subheadline)
                    } label: { Label("Fiscalità: verifica anche sotto 5.000 €", systemImage: "info.circle").font(.subheadline.weight(.semibold)) }
                    Text("Se fai ripetizioni regolarmente, verifica l'inquadramento adesso: la cifra da sola non determina gli obblighi.").font(.caption).foregroundStyle(PivotTheme.muted)
                }
                if store.data.clients.isEmpty {
                    PivotCard {
                        ActionRow(title: "Aggiungi il primo contatto", subtitle: "Ripetizioni, lavoro o altre entrate.", icon: "person.badge.plus")
                        Button("Aggiungi contatto") { addingClient = true }.buttonStyle(PivotPrimaryButton()).disabled(store.locked)
                    }
                } else {
                    Button { addingLesson = true } label: { Label("Registra attività", systemImage: "plus.circle.fill") }.buttonStyle(PivotPrimaryButton()).disabled(store.locked)
                }
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "Ultimi incassi", detail: String(year))
                    if monthPayments.count > 5 {
                        Button(showAllReceipts ? "Mostra meno" : "Mostra tutto") { showAllReceipts.toggle() }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .accessibilityIdentifier("income-receipts-expand")
                    }
                    if monthPayments.isEmpty { EmptyCard(title: "I tuoi incassi, tutti qui", message: "Quando registri un pagamento, lo ritrovi in questa lista.", icon: "eurosign.arrow.circlepath") }
                    else {
                        PivotCard {
                            ForEach(visibleReceipts) { payment in
                                NavigationLink { IncomeDetailView(entryID: payment.incomeID) } label: { HStack(spacing: 12) {
                                    avatar(payment.clientName)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(payment.clientName).font(.subheadline.weight(.semibold))
                                        Text(payment.date.map { DisplayDate.label($0, format: "d MMM · HH:mm") } ?? "\(payment.year ?? year) · Data incasso non nota").font(.caption).foregroundStyle(PivotTheme.muted)
                                    }
                                    Spacer()
                                    Text("+ \(Money.display(payment.amountCents))").font(.subheadline.weight(.semibold)).foregroundStyle(PivotTheme.accent)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(PivotTheme.muted)
                                }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityIdentifier("receipt-detail-" + payment.id.uuidString)
                                if payment.id != visibleReceipts.last?.id { Divider().overlay(.white.opacity(0.05)) }
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
                    SectionHeading(title: "I tuoi contatti", detail: "\(store.data.clients.count)")
                    let contacts = orderedContacts
                    ForEach(contacts.filter { $0.activityState?.inactive != true }) { contactCard($0) }
                    let inactive = contacts.filter { $0.activityState?.inactive == true }
                    if !inactive.isEmpty {
                        Button { showInactiveContacts.toggle() } label: {
                            HStack {
                                Text("Inattivi (\(inactive.count))").font(.headline)
                                Spacer(); Image(systemName: showInactiveContacts ? "chevron.up" : "chevron.down")
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityValue(showInactiveContacts ? "Espanso" : "Chiuso")
                            .accessibilityIdentifier("income-inactive-contacts")
                        if showInactiveContacts { ForEach(inactive) { contactCard($0) } }
                    }
                    if !store.data.clients.isEmpty { Button { addingClient = true } label: { Label("Aggiungi contatto", systemImage: "person.badge.plus") }.buttonStyle(PivotSecondaryButton()).disabled(store.locked) }
                }
            }.navigationTitle("Entrate")
                .sheet(isPresented: $addingClient) { ClientForm() }
                .sheet(isPresented: $addingLesson) { LessonForm(clients: store.data.clients) }
                .sheet(isPresented: $importingHistory) { HistoricalIncomeView() }
                .sheet(isPresented: $exporting) { if let exportFile { ShareSheet(items: [exportFile]) } }
                .sheet(isPresented: $editingOpening) { OpeningIncomeForm(year: year) }
                .onChange(of: chartRange) { _, _ in selectedBar = nil }
                .onChange(of: year) { _, _ in selectedBar = nil }
                .onChange(of: chartStyle) { _, _ in selectedBar = nil }
                .task(id: store.data.updatedAt) {
                    let data = store.data
                    let ids = await Task.detached(priority: .utility) {
                        ClientActivity.sorted(data.clients, data: data, now: Date()).map(\.id)
                    }.value
                    guard !Task.isCancelled, data.updatedAt == store.data.updatedAt else { return }
                    orderedContactIDs = ids
                    await calendar.refreshContactActivity(store: store)
                }
        }
    }
    private func contactCard(_ client: Client) -> some View {
        NavigationLink { ClientDetailView(client: client) } label: {
            PivotCard {
                HStack(spacing: 12) {
                    avatar(client.name)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(client.name).font(.headline).foregroundStyle(PivotTheme.text)
                        Text(client.activityKind == .gift ? client.activityKind.label : "\(client.activityKind.label) · \(Money.display(client.rateCents))\(client.billingMode == .hourly ? "/h" : "")").font(.caption).foregroundStyle(PivotTheme.muted)
                    }
                    Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(PivotTheme.muted)
                }
            }
        }.buttonStyle(.plain).accessibilityIdentifier("client-detail-" + client.id.uuidString)
    }
    private var balanceCarousel: some View {
        VStack(spacing: 10) {
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        balance(width: geometry.size.width)
                            .frame(height: carouselHeight, alignment: .top).id(0)
                            .accessibilityHidden(balancePage != 0)
                        measuredIncomePage(2, width: geometry.size.width) { SavingsPanel(cardHeight: carouselHeights[0] ?? 280) }
                            .frame(width: geometry.size.width).frame(height: carouselHeight, alignment: .top).id(2)
                            .accessibilityHidden(balancePage != 2)
                        incomeChart(width: geometry.size.width)
                            .frame(height: carouselHeight, alignment: .top).id(1)
                            .accessibilityHidden(balancePage != 1)
                    }.scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: Binding<Int?>(get: { balancePage }, set: { if let page = $0 { balancePage = page } }))
                .accessibilityLabel("Riepilogo, Salvadanaio e grafico delle entrate, scorri orizzontalmente")
                .accessibilityIdentifier("income-carousel")
                .modifier(IncomeCarouselDiagnostics(page: balancePage, heights: carouselHeights, height: carouselHeight))
            }
            .frame(height: carouselHeight)
            .animation(.easeInOut(duration: 0.22), value: carouselHeight)

            // Navigation lives outside the cards: it cannot cover chart labels
            // or the explanation, even with larger accessibility text.
            HStack(spacing: 20) {
                incomePageButton("Riepilogo", page: 0)
                incomePageButton("Salvadanaio", page: 2)
                incomePageButton("Grafico", page: 1)
            }
        }
    }
    private func incomePageButton(_ title: String, page: Int) -> some View {
        Button { withAnimation { balancePage = page } } label: {
            HStack(spacing: 6) {
                Circle().fill(balancePage == page ? (page == 2 ? Color(pivotHex: "FFB56B") : PivotTheme.accent) : PivotTheme.muted).frame(width: 7, height: 7)
                Text(title).font(.caption.weight(balancePage == page ? .semibold : .regular))
            }.foregroundStyle(balancePage == page ? (page == 2 ? Color(pivotHex: "FFB56B") : PivotTheme.accent) : PivotTheme.muted)
                .padding(.vertical, 8)
                .frame(minHeight: 44)
        }.buttonStyle(.plain)
            .accessibilityAddTraits(balancePage == page ? .isSelected : [])
            .accessibilityIdentifier("income-page-\(page)")
    }
    private func measuredIncomePage<Content: View>(_ page: Int, width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        // Measure the actual page at its final width, independently of the
        // horizontal stack's tallest neighbour or an initial ideal-size probe.
        content().frame(width: width, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { geometry in geometry.size.height } action: { height in
                guard height.isFinite, height > 0, abs((carouselHeights[page] ?? 0) - height) > 1 else { return }
                carouselHeights[page] = height
            }
    }
    private func balance(width: CGFloat) -> some View {
        measuredIncomePage(0, width: width) {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label {
                    Text("Incassato nell’anno").accessibilityIdentifier("income-summary-title")
                } icon: { Image(systemName: "eurosign.circle.fill") }.font(.subheadline)
                Spacer()
                Picker("Anno", selection: Binding(get: { year }, set: { selectedYear = $0 == currentYear ? nil : $0 })) { ForEach(years, id: \.self) { Text(String($0)).tag($0) } }.pickerStyle(.menu)
            }.foregroundStyle(PivotTheme.accent)
            Text(Money.display(annualTotal)).foregroundStyle(balanceColor).font(.system(size: 42, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1).accessibilityIdentifier("income-summary-total")
            HStack {
                Text("1 gennaio – 31 dicembre \(year)").font(.caption).foregroundStyle(PivotTheme.muted)
                Spacer()
                Text("Da incassare \(Money.display(outstanding.reduce(0) { $0 + $1.outstandingCents }))").font(.caption.weight(.semibold)).foregroundStyle(PivotTheme.amber)
            }
            if let unassigned = ledger.openingCents[String(year)], unassigned > 0 {
                Text("Incassi da attribuire · \(Money.display(unassigned))").font(.caption).foregroundStyle(PivotTheme.muted)
                    .accessibilityIdentifier("income-unassigned-opening")
            }
            if let progress = ledger.warningProgress(total: annualTotal) {
                Label(progress >= 1 ? "Riferimento INPS raggiunto: verifica gli adempimenti" : "Ti avvicini al riferimento INPS: \(Money.display(max(0, ledger.referenceCents - annualTotal))) rimanenti", systemImage: "exclamationmark.triangle.fill").font(.caption.weight(.semibold)).foregroundStyle(balanceColor)
            }
            Text("Riferimento INPS 5.000 € · avviso da 4.500 €. Non è un limite esente da tasse. Il nuovo anno riparte da zero, senza cancellare lo storico.").font(.caption).foregroundStyle(PivotTheme.muted)
        }.padding(24).frame(maxWidth: .infinity, alignment: .topLeading)
        }
            .background(LinearGradient(colors: [Color(pivotHex: "22493F"), Color(pivotHex: "1C2C41"), PivotTheme.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(PivotTheme.accent.opacity(0.18)))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("income-summary")
    }
    private func incomeChart(width: CGFloat) -> some View {
        measuredIncomePage(1, width: width) {
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
                if chartStyle == .bars, let point = chartPoints.first(where: { $0.label == selectedBar }) {
                    IncomeBarReadout(label: point.label, cents: point.amountCents,
                                     identifier: "income-bar-value") { selectedBar = nil }
                }
                Chart(chartPoints) { point in
                    switch chartStyle {
                    case .bars:
                        BarMark(x: .value("Periodo", point.label), y: .value("Euro", point.euros)).foregroundStyle(PivotTheme.accent.gradient)
                            .opacity(selectedBar == nil || selectedBar == point.label ? 1 : 0.4)
                            .accessibilityLabel(Text(point.label)).accessibilityValue(Text(Money.display(point.amountCents)))
                    case .line:
                        LineMark(x: .value("Periodo", point.label), y: .value("Euro", point.euros)).foregroundStyle(PivotTheme.blue).interpolationMethod(.catmullRom)
                        PointMark(x: .value("Periodo", point.label), y: .value("Euro", point.euros)).foregroundStyle(PivotTheme.blue)
                    case .area:
                        AreaMark(x: .value("Periodo", point.label), y: .value("Euro", point.euros)).foregroundStyle(LinearGradient(colors: [PivotTheme.blue.opacity(0.65), PivotTheme.blue.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Periodo", point.label), y: .value("Euro", point.euros)).foregroundStyle(PivotTheme.blue)
                    }
                }.chartYScale(domain: 0...max(1, (chartPoints.map(\.euros).max() ?? 0) * 1.15))
                    .chartXSelection(value: $selectedBar)
                    .chartGesture { proxy in
                        SpatialTapGesture().onEnded { value in
                            if chartStyle == .bars { proxy.selectXValue(at: value.location.x) }
                        }
                    }
                    .chartYAxisLabel("€").frame(height: 205)
                    .accessibilityIdentifier("income-chart-plot")
                    .onChange(of: chartPoints.map(\.key)) { _, _ in selectedBar = nil }
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
                let cents = store.data.payments.filter { $0.occurred(from: date, to: next) }.reduce(0) { $0 + $1.amountCents }
                return IncomeChartPoint(key: PivotDate.key(date), label: DisplayDate.label(date, format: "d/M"), amountCents: cents)
            }
        case .months:
            let now = Date(), components = calendar.dateComponents([.year, .month], from: now)
            guard let currentMonth = calendar.date(from: components) else { return [] }
            return (0..<12).reversed().compactMap { offset -> IncomeChartPoint? in
                guard let date = calendar.date(byAdding: .month, value: -offset, to: currentMonth), let next = calendar.date(byAdding: .month, value: 1, to: date) else { return nil }
                let cents = store.data.payments.filter { $0.occurred(from: date, to: next) }.reduce(0) { $0 + $1.amountCents }
                return IncomeChartPoint(key: DisplayDate.label(date, format: "yyyy-MM"), label: DisplayDate.label(date, format: "MMM yy"), amountCents: cents)
            }
        case .year:
            return (1...12).compactMap { month -> IncomeChartPoint? in
                guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)), let next = calendar.date(byAdding: .month, value: 1, to: date) else { return nil }
                let cents = store.data.payments.filter { $0.occurred(from: date, to: next) }.reduce(0) { $0 + $1.amountCents }
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

private struct IncomeCarouselDiagnostics: ViewModifier {
    let page: Int
    let heights: [Int: CGFloat]
    let height: CGFloat
    @ViewBuilder func body(content: Content) -> some View {
        #if DEBUG && targetEnvironment(simulator)
        content.accessibilityValue("layout page=\(page) viewport=\(height) summary=\(heights[0] ?? 0) savings=\(heights[2] ?? 0) chart=\(heights[1] ?? 0)")
        #else
        content
        #endif
    }
}

struct ClientForm: View {
    @EnvironmentObject var store: PivotStore
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var rate = ""
    @State private var cadence: PaymentCadence = .everyLesson
    @State private var aliases = ""
    @State private var activity: IncomeActivityKind = .lesson
    @State private var billing: IncomeBilling = .hourly
    @State private var defaults = ClientDefaults()
    @State private var savingContact = false
    @State private var message: String?
    var editingClient: Client? = nil
    private var existing: [Client] { ClientRegistry.named(name, clients: store.data.clients) }
    private var saveTitle: String { editingClient != nil || existing.count == 1 ? "Salva contatto" : "Aggiungi contatto" }
    private var rateValue: Int? { rate.trimmingCharacters(in: .whitespaces).isEmpty && activity != .lesson ? 0 : Money.cents(from: rate) }
    var body: some View {
        NavigationStack {
            PivotScreen {
                PivotHeader(title: editingClient == nil ? "Nuovo contatto" : "Modifica contatto", subtitle: "Le modifiche non cambiano gli importi già registrati.")
                PivotCard {
                    Label("Contatto", systemImage: "person.fill").font(.headline).foregroundStyle(PivotTheme.blue)
                    TextField("Nome", text: $name).textContentType(.name).accessibilityIdentifier("client-name").padding(14).background(PivotTheme.raised, in: RoundedRectangle(cornerRadius: 12))
                    Picker("Attività abituale", selection: $activity) { ForEach(IncomeActivityKind.allCases, id: \.self) { Text($0.label).tag($0) } }.accessibilityIdentifier("client-activity")
                    if activity != .lesson && activity != .gift {
                        Picker("Compenso", selection: $billing) { Text("A ore").tag(IncomeBilling.hourly); Text("Importo fisso").tag(IncomeBilling.fixed) }.accessibilityIdentifier("client-billing")
                    }
                    Label(activity == .gift ? "Importo abituale, facoltativo" : (billing == .hourly ? "Tariffa all'ora" : "Importo abituale, facoltativo"), systemImage: "eurosign.circle").font(.subheadline.weight(.semibold))
                    HStack {
                        TextField("Ad esempio 18", text: $rate).keyboardType(.decimalPad).accessibilityIdentifier("client-rate")
                        Text(billing == .hourly ? "€/h" : "€").foregroundStyle(PivotTheme.muted)
                    }.padding(14).background(PivotTheme.raised, in: RoundedRectangle(cornerRadius: 12))
                if activity != .gift { Picker("Come ti paga di solito?", selection: $cadence) {
                        ForEach(PaymentCadence.allCases, id: \.self) { Text($0 == .everyLesson && activity != .lesson ? "A ogni attività" : $0.label).tag($0) }
                    } }
                    TextField("Altri nomi nel calendario, uno per riga", text: $aliases, axis: .vertical).lineLimit(2...4).accessibilityIdentifier("client-aliases")
                    Text("Aggiungi solo nomi che sai appartenere a questa persona. I casi ambigui richiedono una scelta; i nomi non vengono inviati all’AI online.").font(.caption).foregroundStyle(PivotTheme.muted)
                }
                PivotCard { ClientDefaultsFields(defaults: $defaults) }
                if editingClient == nil && existing.count == 1 {
                    Text("Questo contatto esiste già: aggiornerò il profilo senza creare un doppione.").font(.subheadline).accessibilityIdentifier("client-update-existing")
                } else if existing.contains(where: { $0.id != editingClient?.id }) {
                    Text("Ci sono più profili con questo nome. Apri lo studente da Entrate e scegli Unisci profili, solo se sono davvero la stessa persona.").foregroundStyle(PivotTheme.amber)
                }
                if let message { Text(message).foregroundStyle(PivotTheme.amber) }
                Button(savingContact ? "Salvo…" : saveTitle) {
                    guard !savingContact, let cents = rateValue else { return }
                    var next = store.data
                    do {
                        try ClientRegistry.save(name: name, rateCents: cents, cadence: cadence,
                                                aliases: aliases.components(separatedBy: .newlines), editingID: editingClient?.id,
                                                activity: activity, billing: billing, defaults: defaults, data: &next)
                        if store.change({ $0 = next }) {
                            savingContact = true
                            Task { @MainActor in
                                let persisted = await store.flushPendingWrites()
                                savingContact = false
                                if persisted { dismiss() }
                                else { message = "Il contatto è ancora in memoria ma non è salvato su disco. Riprova prima di chiudere l’app." }
                            }
                        }
                    } catch { message = "Non ho creato un altro profilo. Scegli lo studente esistente o unisci prima i doppioni." }
                }.buttonStyle(PivotPrimaryButton()).accessibilityIdentifier("client-save").disabled(store.locked || savingContact || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || rateValue == nil || !defaults.isValid)
            }.navigationTitle("Contatto").disabled(savingContact).interactiveDismissDisabled(savingContact)
                .onAppear { if let client = editingClient { name = client.name; rate = String(format: "%.2f", Double(client.rateCents) / 100); cadence = client.paymentCadence ?? .everyLesson; aliases = (client.calendarAliases ?? []).joined(separator: "\n"); activity = client.activityKind; billing = client.billingMode; defaults = client.defaults ?? ClientDefaults() } }
                .onChange(of: activity) { _, value in if value == .lesson { billing = .hourly }; if value == .gift { billing = .fixed } }
                .onChange(of: name) { _, _ in
                    if editingClient == nil, existing.count == 1, let client = existing.first {
                        defaults = client.defaults ?? ClientDefaults()
                    }
                    if editingClient == nil, existing.count == 1, rate.isEmpty, let client = existing.first {
                        rate = String(format: "%.2f", Double(client.rateCents) / 100); cadence = client.paymentCadence ?? .everyLesson; activity = client.activityKind; billing = client.billingMode
                    }
                }
                .toolbar { Button("Annulla") { dismiss() }.disabled(savingContact) }
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
    @State private var received = ""
    @State private var receiptDate = Date()
    @State private var operationID = UUID()
    @State private var message: String?
    @State private var notes = ""
    @State private var activityOverride: IncomeActivityKind?
    @State private var billingOverride: IncomeBilling?
    @State private var paymentTiming: PaymentTiming = .everyLesson
    @State private var promisedDate = Date()
    @State private var rememberCadence = false
    init(clients: [Client], selectedClientID: UUID? = nil) { self.clients = clients; _clientID = State(initialValue: selectedClientID ?? clients.first?.id ?? UUID()) }
    var selected: Client? { store.data.clients.first { $0.id == clientID } }
    var activityKind: IncomeActivityKind { activityOverride ?? selected?.activityKind ?? .lesson }
    var billingMode: IncomeBilling { activityKind == .gift ? .fixed : activityKind == .lesson ? .hourly : billingOverride ?? selected?.billingMode ?? .hourly }
    var isLesson: Bool { activityKind == .lesson }
    var hasDuration: Bool { isLesson || billingMode == .hourly }
    var calculated: Int { billingMode == .fixed ? selected?.rateCents ?? 0 : Money.lessonAmount(rateCents: selected?.rateCents ?? 0, minutes: minutes) }
    var finalAmount: Int? { amount.isEmpty ? calculated : Money.cents(from: amount) }
    var receivedAmount: Int? { alreadyPaid ? (received.isEmpty ? finalAmount : Money.cents(from: received)) : 0 }
    var body: some View {
        NavigationStack {
            PivotScreen {
                PivotHeader(title: isLesson ? "Una lezione in più" : "Nuova entrata", subtitle: "Compenso e incasso restano separati.")
                PivotCard {
                    HStack {
                        Label("Contatto", systemImage: "person.fill").font(.subheadline.weight(.semibold))
                        Spacer()
                        Picker("Contatto", selection: $clientID) { ForEach(store.data.clients) { Text($0.name).tag($0.id) } }.pickerStyle(.menu).labelsHidden()
                    }
                    DatePicker(isLesson ? "Data della lezione" : "Data dell’attività", selection: $date)
                    Picker("Tipo di attività", selection: Binding(get: { activityKind }, set: { activityOverride = $0; billingOverride = nil })) {
                        ForEach(IncomeActivityKind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    if activityKind != .lesson && activityKind != .gift {
                        Picker("Compenso", selection: Binding(get: { billingMode }, set: { billingOverride = $0 })) {
                            Text("A ore").tag(IncomeBilling.hourly); Text("Importo fisso").tag(IncomeBilling.fixed)
                        }
                    }
                    if hasDuration { DurationField(title: isLesson ? "Durata della lezione" : "Durata del lavoro", seconds: Binding(get: { minutes * 60 }, set: { minutes = max(1, ($0 ?? 60) / 60) }), maxHours: 8) }
                }
                PivotCard(tint: PivotTheme.accent) {
                    Text(isLesson ? "Compenso della lezione" : "Importo previsto").font(.subheadline).foregroundStyle(PivotTheme.muted)
                    Text(Money.display(finalAmount ?? 0)).font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(PivotTheme.accent)
                    if hasDuration { Text("Calcolato dalla tariffa: \(Money.display(calculated))").font(.caption).foregroundStyle(PivotTheme.muted) }
                    TextField("Importo diverso in euro, se serve", text: $amount).keyboardType(.decimalPad).padding(12).background(PivotTheme.raised, in: RoundedRectangle(cornerRadius: 12)).accessibilityIdentifier("income-manual-compensation")
                    Toggle("Ho già ricevuto un pagamento", isOn: $alreadyPaid).accessibilityIdentifier("income-manual-has-receipt")
                    if alreadyPaid {
                        TextField("Ricevuto in euro, lascia vuoto per il saldo", text: $received).keyboardType(.decimalPad).accessibilityIdentifier("income-manual-received")
                        DatePicker("Data incasso", selection: $receiptDate)
                    }
                    if (receivedAmount ?? 0) < (finalAmount ?? 0) {
                        Text("Da incassare \(Money.display(max(0, (finalAmount ?? 0) - (receivedAmount ?? 0))))").foregroundStyle(PivotTheme.amber)
                        PaymentTermsFields(timing: $paymentTiming, promisedDate: $promisedDate, remember: $rememberCadence, studentName: selected?.name ?? "")
                    }
                }
                PivotCard { TextField("Descrizione o note…", text: $notes, axis: .vertical).lineLimit(3...6) }
                if let message { Text(message).foregroundStyle(PivotTheme.amber) }
                Button(isLesson ? "Registra lezione" : "Registra entrata") { save() }
                    .buttonStyle(PivotPrimaryButton()).disabled(store.locked || (finalAmount ?? 0) <= 0 || receivedAmount == nil || (receivedAmount ?? 0) > (finalAmount ?? 0) || selected == nil)
                    .accessibilityIdentifier("income-manual-save")
            }.navigationTitle(isLesson ? "Lezione" : "Entrata")
                .onAppear { paymentTiming = selected?.paymentCadence?.timing ?? .everyLesson; alreadyPaid = selected?.activityKind == .gift }
                .onChange(of: clientID) { _, id in paymentTiming = store.data.clients.first { $0.id == id }?.paymentCadence?.timing ?? .everyLesson; rememberCadence = false; amount = ""; received = ""; activityOverride = nil; billingOverride = nil; alreadyPaid = selected?.activityKind == .gift }
                .toolbar { Button("Annulla") { dismiss() } }
        }
    }
    private func save() {
        guard let client = selected, let cents = finalAmount, let paid = receivedAmount else { return }
        var next = store.data
        do {
            let timing: PaymentTiming = paid == cents ? .everyLesson : paymentTiming
            try ManualIncome.register(id: operationID, client: client, date: date, minutes: minutes,
                amountCents: cents, receivedCents: paid, paymentDate: receiptDate, notes: notes,
                timing: timing, promisedDate: timing == .chosenDate ? promisedDate : nil,
                activity: activityKind, billing: billingMode, data: &next)
            if rememberCadence && paid < cents { StudentPayments.remember(timing, for: client.id, data: &next) }
            if store.change({ $0 = next }) { dismiss() }
        } catch { message = error.localizedDescription }
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
    @State private var editingAmount = false
    @State private var editingReceipt: Payment?
    var entry: IncomeEntry? { store.data.income.first { $0.id == entryID } }
    var body: some View {
        PivotScreen {
            if let entry {
                PivotHeader(title: entry.clientName, subtitle: "\(DisplayDate.label(entry.date, format: "d MMMM yyyy"))\(entry.hasDuration ? " · \(entry.minutes) min" : "") · \(entry.activityKind.label)")
                PivotCard(tint: entry.outstandingCents > 0 ? PivotTheme.amber : PivotTheme.accent) {
                    Text(entry.outstandingCents > 0 ? "Da incassare" : "Lezione saldata").font(.subheadline).foregroundStyle(PivotTheme.muted)
                    Text(Money.display(entry.outstandingCents > 0 ? entry.outstandingCents : entry.amountCents)).font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(entry.outstandingCents > 0 ? PivotTheme.amber : PivotTheme.accent)
                    HStack { Text("Totale \(Money.display(entry.amountCents))"); Spacer(); Text("Ricevuto \(Money.display(entry.paidCents))") }.font(.caption).foregroundStyle(PivotTheme.muted)
                    if !entry.notes.isEmpty { Text(entry.notes).font(.subheadline) }
                    PaymentDueLabel(due: agenda.paymentDues.first { $0.entryIDs.contains(entry.id) })
                    Button("Correggi compenso della lezione") { editingAmount = true }.buttonStyle(PivotSecondaryButton()).accessibilityIdentifier("income-edit-compensation").disabled(store.locked)
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
                        TextField("Importo ricevuto in euro", text: $payment).keyboardType(.decimalPad).padding(12).background(PivotTheme.raised, in: RoundedRectangle(cornerRadius: 12))
                        Button("Registra importo") { collect(entry, cents: Money.cents(from: payment) ?? 0) }.buttonStyle(PivotPrimaryButton()).disabled(store.locked || (Money.cents(from: payment) ?? 0) <= 0)
                        Button("Registra il saldo completo") { collect(entry, cents: entry.outstandingCents) }.buttonStyle(PivotSecondaryButton()).disabled(store.locked)
                    }
                    if let client = store.data.clients.first(where: { $0.id == entry.clientID }) {
                        NavigationLink("Paga più lezioni / vedi il saldo dello studente") { ClientDetailView(client: client) }.buttonStyle(PivotSecondaryButton())
                    }
                }
                let payments = store.data.payments.filter { $0.incomeID == entry.id }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                if !payments.isEmpty {
                    PivotCard {
                        SectionHeading(title: "Pagamenti ricevuti")
                        ForEach(payments) { p in
                            HStack { Text(p.date.map { DisplayDate.label($0, format: "d MMM yyyy") } ?? "\(p.year ?? 0) · Data incasso non nota").foregroundStyle(PivotTheme.muted); Spacer(); Text("+ \(Money.display(p.amountCents))").foregroundStyle(PivotTheme.accent) }.font(.subheadline)
                            Button("Correggi questo incasso") { editingReceipt = p }.font(.subheadline).accessibilityIdentifier("income-edit-receipt-" + p.id.uuidString).disabled(store.locked)
                            if entry.historicalSource?.receiptID == p.id, entry.historicalSource?.paymentDateAssumed == true {
                                Text("Data impostata alla data della lezione.").font(.caption).foregroundStyle(PivotTheme.muted)
                            }
                        }
                    }
                }
                let edits = (store.data.incomeEdits ?? []).filter { $0.incomeID == entryID }.sorted { $0.editedAt > $1.editedAt }
                if !edits.isEmpty {
                    DisclosureGroup("Correzioni registrate (\(edits.count))") {
                        ForEach(edits) { edit in Text("\(DisplayDate.label(edit.editedAt, format: "d MMM HH:mm")) · \(edit.paymentID == nil ? "Compenso" : "Incasso"): \(Money.display(edit.previousCents)) → \(Money.display(edit.correctedCents))").font(.caption) }
                    }
                }
            } else { EmptyCard(title: "Lezione non disponibile", message: "Torna alle entrate per scegliere una lezione.", icon: "eurosign.circle") }
            if let message { Label(message, systemImage: "info.circle").font(.subheadline).foregroundStyle(PivotTheme.amber) }
        }.navigationTitle("Pagamento")
        .sheet(isPresented: $editingAmount) { IncomeCorrectionForm(incomeID: entryID) }
        .sheet(item: $editingReceipt) { payment in IncomeCorrectionForm(incomeID: entryID, paymentID: payment.id) }
        .onAppear {
            if let entry { timing = StudentPayments.timing(for: entry, data: store.data); promisedDate = entry.promisedPaymentDate ?? Date() }
        }
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
    @EnvironmentObject var agenda: AgendaService
    @EnvironmentObject var calendar: CalendarService
    let client: Client
    @State private var editingClient = false
    @State private var mergingClient = false
    @State private var addingActivity = false
    @State private var activityAlert: String?
    @State private var changingActivity = false
    private var current: Client { store.data.clients.first { $0.id == client.id } ?? client }
    var entries: [IncomeEntry] { store.data.income.filter { $0.clientID == client.id }.sorted { $0.date > $1.date } }
    var body: some View {
        PivotScreen {
            PivotHeader(title: current.name, subtitle: current.activityKind == .lesson ? "\(Money.display(current.rateCents)) all'ora · \(entries.count) lezioni registrate" : "\(current.activityKind.label) · \(entries.count) attività registrate")
            PivotCard {
                HStack {
                    Text("Contatto attivo").font(.headline)
                    Spacer()
                    Toggle("Contatto attivo", isOn: Binding(get: { current.activityState?.inactive != true }, set: changeActivity))
                        .labelsHidden().fixedSize().frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("client-active-toggle")
                        .disabled(store.locked || changingActivity)
                }
                if changingActivity { ProgressView("Verifico gli appuntamenti…") }
                if let next = calendar.nextContactAppointment(client.id) {
                    Text("Prossimo: \(DisplayDate.label(next.start, format: "d MMM yyyy · HH:mm"))")
                        .font(.caption).foregroundStyle(PivotTheme.muted)
                }
                DisclosureGroup("Attivazione automatica") {
                    Text("Dopo 90 giorni senza attività, il contatto passa tra gli inattivi se non ha appuntamenti nei calendari inclusi nei prossimi 4 anni. Una nuova lezione lo riattiva. Lo storico e i pagamenti non cambiano.")
                        .font(.caption).foregroundStyle(PivotTheme.muted)
                    if let issue = calendar.contactActivityProblem { Text(issue).font(.caption).foregroundStyle(PivotTheme.amber) }
                }
            }
            Button("Modifica contatto e predefiniti") { editingClient = true }.buttonStyle(PivotSecondaryButton()).accessibilityIdentifier("client-edit").disabled(store.locked)
            if store.data.clients.count > 1 { Button("Unisci profili dello stesso contatto") { mergingClient = true }.buttonStyle(PivotSecondaryButton()).accessibilityIdentifier("client-merge").disabled(store.locked) }
            ClientIncomeOverview(clientID: client.id)
            Button(current.activityKind == .lesson ? "Aggiungi lezione" : "Aggiungi attività") { addingActivity = true }
                .buttonStyle(PivotPrimaryButton()).accessibilityIdentifier("client-add-activity").disabled(store.locked)
            if current.activityKind != .gift { PivotCard {
                Picker("Come ti paga di solito?", selection: Binding(get: { store.data.clients.first { $0.id == client.id }?.paymentCadence ?? .everyLesson }, set: { value in
                    store.change { data in if let index = data.clients.firstIndex(where: { $0.id == client.id }) { data.clients[index].paymentCadence = value } }
                })) {
                    ForEach(PaymentCadence.allCases, id: \.self) { Text($0 == .everyLesson && current.activityKind != .lesson ? "A ogni attività" : $0.label).tag($0) }
                }.accessibilityIdentifier("student-payment-cadence")
            } }
            if StudentPayments.balance(clientID: client.id, data: store.data) > 0 {
                StudentBalancePaymentView(clientID: client.id, clientName: client.name)
            } else {
                Text("Nessun saldo da incassare.").font(.caption).accessibilityIdentifier("student-balance-clear")
            }
            SectionHeading(title: current.activityKind == .lesson ? "Storico lezioni" : "Storico attività")
            if entries.isEmpty { EmptyCard(title: "Nessuna attività registrata", message: "Aggiungi un’attività a questo contatto.", icon: "person.2.fill") }
            ForEach(entries) { entry in
                NavigationLink { IncomeDetailView(entryID: entry.id) } label: {
                    PivotCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(DisplayDate.label(entry.date, format: "d MMM yyyy"))\(entry.hasDuration ? " · \(entry.minutes) min" : "")").font(.subheadline.weight(.semibold)).foregroundStyle(PivotTheme.text)
                                Text(entry.outstandingCents == 0 ? "Pagata · \(Money.display(entry.amountCents))" : "Da incassare · \(Money.display(entry.outstandingCents))").font(.caption).foregroundStyle(entry.outstandingCents == 0 ? PivotTheme.accent : PivotTheme.amber)
                                if entry.outstandingCents > 0 { PaymentDueLabel(due: agenda.paymentDues.first { $0.entryIDs.contains(entry.id) }) }
                            }
                            Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(PivotTheme.muted)
                        }
                    }
                }.buttonStyle(.plain)
            }
        }.navigationTitle("Contatto")
        .sheet(isPresented: $editingClient) { ClientForm(editingClient: current) }
        .sheet(isPresented: $mergingClient) { ClientMergeForm(targetID: client.id) }
        .sheet(isPresented: $addingActivity) { LessonForm(clients: store.data.clients, selectedClientID: client.id) }
        .alert("Contatto ancora attivo", isPresented: Binding(get: { activityAlert != nil }, set: { if !$0 { activityAlert = nil } })) {
            Button("Va bene", role: .cancel) { activityAlert = nil }
        } message: { Text(activityAlert ?? "") }
    }
    private func changeActivity(_ active: Bool) {
        guard !changingActivity, !store.locked else { return }
        changingActivity = true
        Task {
            defer { changingActivity = false }
            if !active {
                guard await calendar.refreshContactActivity(store: store, force: true) else {
                    activityAlert = calendar.contactActivityProblem ?? "Attendi la verifica del calendario e riprova. Non ho disattivato il contatto."
                    return
                }
                if let next = calendar.nextContactAppointment(client.id) {
                    activityAlert = "Hai già \(next.title) il \(DisplayDate.label(next.start, format: "d MMM yyyy 'alle' HH:mm")). Il contatto resta attivo. Se la lezione non si terrà, modifica prima l’appuntamento."
                    return
                }
            }
            do {
                let data = store.data, scan = calendar.contactActivity, id = client.id
                let clients = try await Task.detached(priority: .userInitiated) {
                    var next = data
                    try ClientActivity.setActive(active, clientID: id, data: &next, scan: scan, now: Date())
                    return next.clients
                }.value
                guard data.updatedAt == store.data.updatedAt else {
                    activityAlert = "I dati sono cambiati durante la verifica. Riprova: il contatto non è stato modificato."
                    return
                }
                _ = store.change { $0.clients = clients }
            } catch { activityAlert = "Gli appuntamenti sono cambiati o non sono verificabili. Non ho modificato il contatto." }
        }
    }
}

struct OpeningIncomeForm: View {
    @EnvironmentObject var store: PivotStore
    @Environment(\.dismiss) var dismiss
    let year: Int
    @State private var total = ""
    var recorded: Int { store.data.payments.filter { $0.year == year }.reduce(0) { $0 + $1.amountCents } }
    var body: some View {
        NavigationStack {
            PivotScreen {
                PivotHeader(title: "Incassi già ricevuti", subtitle: "Anno \(year). Imposta il totale prima di iniziare a usare il registro.")
                PivotCard {
                    TextField("Totale già incassato in euro", text: $total).keyboardType(.decimalPad).padding(14).background(PivotTheme.raised, in: RoundedRectangle(cornerRadius: 12))
                    Text("Include i pagamenti già registrati (\(Money.display(recorded))). Li sottraggo dall'importo pregresso per evitare doppioni. Non creo ricevute o studenti fittizi.").font(.caption).foregroundStyle(PivotTheme.muted)
                    if store.data.savingsBudget != nil { Text("Questa modifica riguarda il totale annuale, non i fondi del Salvadanaio.").font(.caption).foregroundStyle(PivotTheme.amber) }
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
