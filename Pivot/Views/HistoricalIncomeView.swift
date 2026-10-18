import SwiftUI

struct HistoricalIncomeView: View {
    @EnvironmentObject private var store: PivotStore
    @EnvironmentObject private var calendar: CalendarService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var year = PivotDate.calendar.component(.year, from: Date())
    @State private var calendarIDs = Set<String>()
    @State private var events: [CalendarItem] = []
    @State private var clients: [String: UUID] = [:]
    @State private var historicalRates: [UUID: String] = [:]
    @State private var confirmedRates = Set<UUID>()
    @State private var selected = Set<String>()
    @State private var loading = false
    @State private var loaded = false
    @State private var addingClient = false
    @State private var review: Review?
    @State private var message: String?
    @State private var task: Task<Void, Never>?
    @State private var completingDates = false

    private struct Review: Identifiable {
        let id = UUID()
        let quotes: [HistoricalIncome.Quote]
        let result: HistoricalIncome.Result
        let before: Int
        let after: Int
    }
    private var choices: [CalendarChoice] {
        calendar.choices.filter { !store.data.settings.excludedCalendarIDs.contains($0.id)
            && !store.data.settings.excludedCalendarTitles.contains($0.title)
            && !(store.data.settings.excludeHolidays && $0.holiday) }
    }
    private var quotes: [HistoricalIncome.Quote] {
        events.filter { selected.contains($0.id) }.compactMap { status($0).quote }
    }
    private var previousYear: Bool { year < PivotDate.calendar.component(.year, from: Date()) }
    private var assignedClients: [Client] {
        let ids = Set(clients.values)
        return store.data.clients.filter { ids.contains($0.id) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        NavigationStack {
            PivotScreen {
                PivotHeader(title: "Recupera le lezioni", subtitle: "Dal calendario al tuo registro.")
                if store.data.income.contains(where: { entry in
                    guard let source = entry.historicalSource, source.receivedYear == year else { return false }
                    return store.data.payments.contains { $0.id == source.receiptID && $0.date == nil }
                }) {
                    Button("Completa date delle lezioni già recuperate") { completingDates = true }
                        .buttonStyle(PivotSecondaryButton()).disabled(store.locked || loading)
                        .accessibilityIdentifier("history-complete-dates")
                }
                PivotCard {
                    Picker("Anno", selection: $year) {
                        ForEach(Array(1900...max(1900, PivotDate.calendar.component(.year, from: Date()))).reversed(), id: \.self) { Text(String($0)).tag($0) }
                    }.accessibilityIdentifier("history-year")
                    ForEach(choices) { choice in
                        Toggle(choice.title, isOn: Binding(get: { calendarIDs.contains(choice.id) }, set: { value in
                            if value { calendarIDs.insert(choice.id) } else { calendarIDs.remove(choice.id) }
                            clearPreview()
                        }))
                    }
                    Button(loading ? "Lettura in corso…" : "Cerca lezioni") { load() }
                        .buttonStyle(PivotSecondaryButton()).disabled(loading || store.locked || calendarIDs.isEmpty)
                        .accessibilityIdentifier("history-load")
                }.disabled(loading)
                if loaded {
                    if previousYear, !assignedClients.isEmpty {
                        PivotCard {
                            SectionHeading(title: "Tariffe nel \(year)", detail: "Solo per questo recupero")
                            ForEach(assignedClients) { client in historicalRateRow(client) }
                        }.disabled(loading || store.locked)
                    }
                    HStack {
                        SectionHeading(title: "Attività trovate", detail: String(events.count))
                        Spacer()
                        Button("Seleziona pronte") {
                            selected = Set(events.filter { status($0).quote != nil }.map(\.id))
                        }.disabled(loading || store.locked).accessibilityIdentifier("history-select-ready")
                    }
                    Button { addingClient = true } label: { Label("Aggiungi contatto", systemImage: "person.badge.plus") }
                        .buttonStyle(PivotSecondaryButton()).disabled(store.locked || loading)
                    LazyVStack(spacing: 12) { ForEach(events) { event in row(event) } }.disabled(loading || store.locked)
                    if events.isEmpty { EmptyCard(title: "Nessuna lezione da recuperare", message: "Controlla anno e calendari selezionati.", icon: "calendar") }
                    Button("Rivedi \(quotes.count) lezioni") { prepareReview() }
                        .buttonStyle(PivotPrimaryButton()).disabled(loading || store.locked || quotes.isEmpty)
                        .accessibilityIdentifier("history-review")
                }
                if let message { Text(message).font(.subheadline).foregroundStyle(PivotTheme.amber).accessibilityIdentifier("history-message") }
            }.navigationTitle("Storico dal calendario")
                .toolbar { Button("Chiudi") { task?.cancel(); dismiss() } }
                .onChange(of: year) { _, _ in clearPreview() }
                .onChange(of: scenePhase) { _, phase in if phase == .background { task?.cancel(); review = nil; loading = false } }
                .onDisappear { task?.cancel() }
                .task {
                    await calendar.refresh(settings: store.data.settings, force: true)
                    calendarIDs = Set(choices.filter { EventCoalescer.normalized($0.title) == "lavoro" }.map(\.id))
                }
                .sheet(isPresented: $addingClient) { ClientForm() }
                .sheet(item: $review) { value in HistoricalIncomeConfirmation(review: value.quotes, result: value.result, before: value.before, after: value.after) { await confirm(value) } }
                .confirmationDialog("Usare la data delle lezioni per gli incassi senza data?", isPresented: $completingDates, titleVisibility: .visible) {
                    Button("Completa date") {
                        var next = store.data
                        do {
                            let count = try HistoricalIncome.completePaymentDates(year: year, data: &next)
                            if store.change({ $0 = next }) { message = "\(count) date completate. Importi e fondi disponibili invariati." }
                        } catch { message = error.localizedDescription }
                    }
                    Button("Annulla", role: .cancel) { }
                } message: {
                    Text("Solo per le lezioni importate nell'anno scelto: l'incasso senza data userà il giorno della lezione. Non aggiunge soldi e non cambia gli incassi normali.")
                }
        }
    }

    private func status(_ event: CalendarItem) -> (quote: HistoricalIncome.Quote?, message: String?) {
        if HistoricalIncome.existingEntry(for: event, data: store.data) != nil { return (nil, "Già registrata") }
        guard let client = clients[event.id] else { return (nil, "Scegli il contatto e verifica la tariffa") }
        do {
            let rate: Int?
            if previousYear {
                guard confirmedRates.contains(client), let contact = store.data.clients.first(where: { $0.id == client }),
                      let value = Money.cents(from: historicalRates[client] ?? rateText(contact)), value > 0 else {
                    return (nil, "Conferma la tariffa del contatto per il \(year)")
                }
                rate = value
            } else { rate = nil }
            return (try HistoricalIncome.quote(event, clientID: client, year: year, now: Date(), data: store.data,
                confirmedRateCents: rate), nil)
        }
        catch { return (nil, error.localizedDescription) }
    }

    private func rateText(_ client: Client) -> String { String(format: "%.2f", Double(client.rateCents) / 100) }
    private func unselectLessons(for clientID: UUID) {
        selected = Set(selected.filter { clients[$0] != clientID })
        review = nil
    }
    private func historicalRateRow(_ client: Client) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(client.name).font(.headline)
            TextField("Euro all’ora", text: Binding(get: { historicalRates[client.id] ?? rateText(client) }, set: { value in
                historicalRates[client.id] = value; confirmedRates.remove(client.id); unselectLessons(for: client.id)
            })).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("history-rate-" + client.id.uuidString)
            Toggle("Confermo la tariffa per il \(year)", isOn: Binding(get: { confirmedRates.contains(client.id) }, set: { value in
                if value { confirmedRates.insert(client.id) } else { confirmedRates.remove(client.id) }
                unselectLessons(for: client.id)
            })).disabled((Money.cents(from: historicalRates[client.id] ?? rateText(client)) ?? 0) <= 0)
                .accessibilityIdentifier("history-rate-confirm-" + client.id.uuidString)
            Text("La tariffa attuale del contatto non cambia.").font(.caption).foregroundStyle(PivotTheme.muted)
        }
    }

    private func row(_ event: CalendarItem) -> some View {
        let state = status(event)
        return PivotCard {
            Text(event.title).font(.headline)
            Text("\(DisplayDate.label(event.start, format: "d MMM yyyy · HH:mm")) · \(event.durationMinutes) min").font(.caption).foregroundStyle(PivotTheme.muted)
            if HistoricalIncome.existingEntry(for: event, data: store.data) == nil {
                Picker("Contatto", selection: Binding<UUID?>(get: { clients[event.id] }, set: { value in clients[event.id] = value; selected.remove(event.id) })) {
                    Text("Da scegliere").tag(UUID?.none)
                    ForEach(store.data.clients.filter { $0.activityKind == .lesson && $0.billingMode == .hourly }) { client in Text("\(client.name) · \(Money.display(client.rateCents))/h").tag(Optional(client.id)) }
                }.accessibilityIdentifier("history-client-" + event.id)
            }
            if let quote = state.quote {
                Toggle("\(Money.display(quote.amountCents)) · Importa", isOn: Binding(get: { selected.contains(event.id) }, set: { value in
                    if value { selected.insert(event.id) } else { selected.remove(event.id) }
                })).accessibilityIdentifier("history-select-" + event.id)
            } else if let text = state.message { Text(text).font(.caption).foregroundStyle(PivotTheme.amber) }
        }
    }
    private func clearPreview() {
        events = []; selected = []; clients = [:]; historicalRates = [:]; confirmedRates = []
        loaded = false; review = nil; message = nil
    }

    private func load() {
        task?.cancel(); loading = true; message = nil
        let selectedYear = year, ids = calendarIDs, settings = store.data.settings
        task = Task {
            defer { loading = false }
            do {
                let fresh = try await calendar.incomeHistory(year: selectedYear, calendarIDs: ids, settings: settings)
                try Task.checkCancellation()
                events = EventCoalescer.unique(fresh, data: store.data); selected = []; clients = [:]
                historicalRates = [:]; confirmedRates = []
                for event in events {
                    clients[event.id] = StudentRecognition.recognize(title: event.title, clients: store.data.clients).client?.id
                }
                loaded = true
            } catch is CancellationError { }
            catch { message = error.localizedDescription }
        }
    }

    private func prepareReview() {
        let items = quotes, original = store.data, version = store.data.updatedAt
        guard !items.isEmpty else { return }
        loading = true
        task = Task {
            defer { loading = false }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    var copy = original
                    return try HistoricalIncome.apply(items, freshEvents: items.map(\.event), now: Date(), assumePaidOnActivityDate: true, data: &copy)
                }.value
                try Task.checkCancellation()
                guard version == store.data.updatedAt else { throw HistoricalIncomeError.changed }
                let before = (original.ledger ?? AnnualLedger()).total(year: year, payments: original.payments)
                review = Review(quotes: items, result: result, before: before, after: before + result.extraAnnualCents)
            } catch is CancellationError { }
            catch { message = error.localizedDescription }
        }
    }

    private func confirm(_ value: Review) async -> String? {
        do {
            let raw = try await calendar.incomeHistory(year: year, calendarIDs: calendarIDs, settings: store.data.settings)
            try Task.checkCancellation()
            let original = store.data, version = original.updatedAt
            let fresh = EventCoalescer.unique(raw, data: original)
            let updated = try await Task.detached(priority: .userInitiated) {
                var next = original
                let result = try HistoricalIncome.apply(value.quotes, freshEvents: fresh, now: Date(), expectedAnnualTotal: value.before, assumePaidOnActivityDate: true, data: &next)
                return (next, result)
            }.value
            try Task.checkCancellation()
            guard version == store.data.updatedAt, updated.1 == value.result else { throw HistoricalIncomeError.changed }
            if store.change({ $0 = updated.0 }) {
                review = nil; selected = []
                message = "\(updated.1.lessons) lezioni recuperate. Fondi del Salvadanaio invariati."
                return nil
            }
            return store.error ?? "Attendi il caricamento del registro."
        } catch { return error.localizedDescription }
    }
}

private struct HistoricalIncomeConfirmation: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let review: [HistoricalIncome.Quote]
    let result: HistoricalIncome.Result
    let before: Int
    let after: Int
    let confirm: () async -> String?
    @State private var paid = false
    @State private var saving = false
    @State private var message: String?
    @State private var task: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            Form {
                Section("Riepilogo") {
                    LabeledContent("Lezioni", value: String(result.lessons))
                    LabeledContent("Compensi ricostruiti", value: Money.display(result.receiptsCents))
                    LabeledContent("Già nel pregresso", value: Money.display(result.openingAttributedCents))
                    LabeledContent("Totale annuale", value: Money.display(after)).accessibilityIdentifier("history-annual-after")
                    Text("Prima: \(Money.display(before)). Fondi disponibili del Salvadanaio invariati.").font(.caption)
                }
                Section {
                    Toggle("Confermo: queste lezioni sono state svolte e già pagate nell’anno scelto", isOn: $paid).accessibilityIdentifier("history-paid-confirmation")
                    Text("Per queste lezioni già pagate userò la data della lezione come data predefinita dell'incasso. È una tua convenzione di registrazione, non una data bancaria verificata.").font(.caption)
                }
                Section("Lezioni selezionate") {
                    ForEach(review) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.clientName)
                            Text("\(DisplayDate.label(item.event.start, format: "d MMM yyyy")) · \(item.minutes) min · \(Money.display(item.amountCents))").font(.caption)
                            Text("\(Money.display(item.rateCents))/h").font(.caption)
                        }
                    }
                }
                if let message { Text(message).foregroundStyle(PivotTheme.amber).accessibilityIdentifier("history-confirm-error") }
                Button(saving ? "Verifica in corso…" : "Importa lezioni") {
                    saving = true
                    task = Task { message = await confirm(); saving = false; if message == nil, !Task.isCancelled { dismiss() } }
                }.disabled(!paid || saving).accessibilityIdentifier("history-confirm-import")
            }.navigationTitle("Conferma lo storico")
                .toolbar { Button("Annulla") { task?.cancel(); dismiss() } }
                .onDisappear { task?.cancel() }
                .onChange(of: scenePhase) { _, phase in if phase == .background { task?.cancel(); dismiss() } }
        }
    }
}
