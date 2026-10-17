import SwiftUI

struct LessonLogisticsView: View {
    @EnvironmentObject var store: PivotStore
    @EnvironmentObject var calendar: CalendarService
    @Environment(\.dismiss) var dismiss
    let event: CalendarItem
    var onDefer: (() -> Void)? = nil
    @State private var logistics = LessonLogistics(studentName: "", place: .undecided)
    @State private var loaded = false
    @State private var selectedOriginID: UUID?
    @State private var updateUsualEstimate = false
    @State private var message: String?
    private var contact: Client? { StudentRecognition.existingClient(named: logistics.studentName, clients: store.data.clients) }
    private var origins: [ClientTravelOrigin] { contact?.defaults?.origins ?? [] }
    private var contactFields: some View {
        Group {
                    Text(event.title).font(.headline)
                    TextField("Conferma il nome dello studente", text: Binding(get: { logistics.studentName }, set: {
                        logistics = LessonLogistics(studentName: $0, place: .undecided); selectedOriginID = nil; updateUsualEstimate = false
                    }))
                    Button("Proponi i dati del contatto") { applyLastChoice() }.font(.caption).frame(minHeight: 44)
                    Picker("Metodo di pagamento previsto", selection: Binding(get: { logistics.paymentMethod ?? .unspecified }, set: { logistics.paymentMethod = $0 })) {
                        ForEach(ClientPaymentMethod.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.accessibilityIdentifier("lesson-payment-method")
                    Picker("Chi si sposta?", selection: Binding(get: { logistics.place }, set: { logistics.place = $0; invalidateTravel() })) {
                        ForEach(LessonPlace.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    TextField("Indirizzo / luogo (facoltativo)", text: Binding(get: { logistics.address }, set: { logistics.address = $0; invalidateTravel() }))
        }
    }
    private var departureFields: some View {
        Group {
                    if !origins.isEmpty {
                        Picker("Partenza di questa lezione", selection: Binding<UUID?>(get: { selectedOriginID }, set: { id in
                            selectedOriginID = id
                            updateUsualEstimate = false
                            if let origin = origins.first(where: { $0.id == id }) {
                                logistics = ClientDefaults.applying(origin, to: logistics)
                            } else {
                                logistics.departure = nil; logistics.travelBeforeMinutes = 0; logistics.travelAfterMinutes = 0; invalidateTravel()
                            }
                        })) {
                            Text("Altra / da scegliere").tag(UUID?.none)
                            ForEach(origins) { Text($0.name).tag(Optional($0.id)) }
                        }.accessibilityIdentifier("lesson-origin")
                    }
                    TextField("Partenza effettiva (es. Casa)", text: Binding(get: { logistics.departure?.name ?? "" }, set: { value in
                        if logistics.departure == nil { logistics.departure = ClientTravelOrigin() }
                        logistics.departure?.name = value; selectedOriginID = nil; invalidateTravel()
                    })).accessibilityIdentifier("lesson-origin-name")
                    TextField("Indirizzo di partenza (facoltativo)", text: Binding(get: { logistics.departure?.address ?? "" }, set: { value in
                        if logistics.departure == nil { logistics.departure = ClientTravelOrigin() }
                        logistics.departure?.address = value; selectedOriginID = nil; invalidateTravel()
                    }))
                    Picker("Mezzo di questa lezione", selection: Binding(get: { logistics.departure?.mode ?? .unspecified }, set: { value in
                        if logistics.departure == nil { logistics.departure = ClientTravelOrigin() }
                        logistics.departure?.mode = value; selectedOriginID = nil; invalidateTravel()
                    })) { ForEach(ClientTravelMode.allCases, id: \.self) { Text($0.label).tag($0) } }
        }
    }
    private var travelFields: some View {
        Group {
                    DurationField(title: "Viaggio per arrivare", seconds: Binding(get: { logistics.travelBeforeMinutes * 60 }, set: { logistics.travelBeforeMinutes = ($0 ?? 0) / 60; invalidateTravel() }), maxHours: 4)
                    DurationField(title: "Viaggio dopo la lezione", seconds: Binding(get: { logistics.travelAfterMinutes * 60 }, set: { logistics.travelAfterMinutes = ($0 ?? 0) / 60; invalidateTravel() }), maxHours: 4)
                    Toggle("Ho verificato i tempi di viaggio", isOn: $logistics.travelConfirmed)
                        .accessibilityIdentifier("lesson-travel-confirm")
                    if selectedOriginID != nil, logistics.travelConfirmed,
                       let defaults = contact?.defaults, defaults.address == logistics.address, defaults.place == logistics.place {
                        Toggle("Aggiorna anche la stima abituale di questa partenza", isOn: $updateUsualEstimate)
                            .accessibilityIdentifier("lesson-update-estimate")
                    }
                    Text("Conferma anche se il viaggio è zero. Non inventiamo un tragitto da un indirizzo incompleto.").font(.caption).foregroundStyle(PivotTheme.muted)
                    if logistics.travelConfirmed {
                        Text("Parti alle \(PivotDate.time(event.start.addingTimeInterval(-Double(logistics.travelBeforeMinutes) * 60)))").foregroundStyle(PivotTheme.accent)
                    }
                    if !validDeparture {
                        Text("Indica un nome per la partenza e controlla i suoi dati.").font(.caption).foregroundStyle(PivotTheme.amber)
                    }
                    if logistics.departure != nil {
                        Button("Rimuovi partenza di questa lezione", role: .destructive) {
                            logistics.departure = nil; selectedOriginID = nil
                            logistics.travelBeforeMinutes = 0; logistics.travelAfterMinutes = 0; invalidateTravel()
                        }.frame(minHeight: 44)
                    }
        }
    }
    var body: some View {
        NavigationStack {
            PivotScreen {
                PivotHeader(title: "Dove fai la lezione?", subtitle: "\(PivotDate.shortDate(event.start)) · \(PivotDate.time(event.start))–\(PivotDate.time(event.end))")
                PivotCard { contactFields; departureFields; travelFields }
                Text("La scelta vale solo per questa lezione. Sarà proposta, non confermata automaticamente, la prossima volta.").font(.caption).foregroundStyle(PivotTheme.muted)
                if let message { Text(message).font(.caption).foregroundStyle(PivotTheme.amber) }
                Button("Conferma questa lezione") { save() }.buttonStyle(PivotPrimaryButton()).disabled(store.locked || logistics.studentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !validDeparture)
                    .accessibilityIdentifier("lesson-logistics-save")
                Button("Più tardi") { onDefer?(); dismiss() }.buttonStyle(PivotSecondaryButton())
            }.navigationTitle("Ripetizioni")
                .onAppear {
                    guard !loaded else { return }
                    if let current = store.record(for: event).logistics, current.isConfirmed(for: event) { logistics = current }
                    else {
                        logistics.studentName = LessonLogistics.suggestedName(event, clients: store.data.clients)
                        applyLastChoice()
                        if !event.location.isEmpty { logistics.address = event.location }
                    }
                    loaded = true
                }
                .onChange(of: logistics.travelConfirmed) { _, value in if !value { updateUsualEstimate = false } }
        }.interactiveDismissDisabled(onDefer != nil)
    }
    private var validDeparture: Bool { logistics.departure?.isValid ?? true }
    private func invalidateTravel() { logistics.travelConfirmed = false; logistics.confirmedAt = nil; updateUsualEstimate = false }
    private func applyLastChoice() {
        let name = logistics.studentName
        selectedOriginID = nil
        updateUsualEstimate = false
        if let defaults = contact?.defaults {
            logistics = defaults.proposal(studentName: name, calendarLocation: event.location)
        } else if let previous = store.data.lessonDefaults?[LessonLogistics.key(name)] {
            logistics = previous; logistics.studentName = name; logistics.confirmedAt = nil; logistics.travelConfirmed = false
            // Last time's origin is not evidence of today's departure.
            logistics.departure = nil; logistics.travelBeforeMinutes = 0; logistics.travelAfterMinutes = 0
        }
    }
    private func save() {
        guard validDeparture, let current = Planner.effectiveEvents(calendar.events, data: store.data).first(where: { $0.id == event.id }),
              current.start == event.start, current.end == event.end, current.location == event.location, current.title == event.title else {
            store.error = "Questa lezione è stata cancellata o è cambiata. Aggiorna il calendario."; return
        }
        logistics.studentName = logistics.studentName.trimmingCharacters(in: .whitespacesAndNewlines)
        logistics.confirmedAt = Date()
        logistics.eventTitleAtConfirmation = current.title
        logistics.calendarLocationAtConfirmation = current.location
        logistics.eventStartAtConfirmation = current.start
        logistics.eventEndAtConfirmation = current.end
        // Snapshot actual, confirmed estimates without overwriting the profile.
        if logistics.departure != nil {
            logistics.departure?.beforeMinutes = logistics.travelBeforeMinutes
            logistics.departure?.afterMinutes = logistics.travelAfterMinutes
        }
        var calibrated: ClientDefaults?
        if updateUsualEstimate {
            do {
                guard let defaults = contact?.defaults, selectedOriginID == logistics.departure?.id else { throw ClientRegistry.Failure.invalid }
                calibrated = try defaults.calibrated(using: logistics)
            } catch { message = "I dati del tragitto sono cambiati. Ricontrolla partenza e tempi prima di aggiornare la stima."; return }
        }
        var record = store.record(for: current); record.logistics = logistics; record.snapshot = current; record.updatedAt = Date()
        var rule = store.rule(for: current)
        rule.travelBeforeMinutes = logistics.travelBeforeMinutes; rule.travelAfterMinutes = logistics.travelAfterMinutes; rule.travelConfirmed = logistics.travelConfirmed
        if store.change({ data in
            data.records[current.id] = record; data.rules[current.id] = rule
            var defaults = data.lessonDefaults ?? [:]; defaults[LessonLogistics.key(logistics.studentName)] = logistics; data.lessonDefaults = defaults
            if let calibrated, let id = contact?.id, let index = data.clients.firstIndex(where: { $0.id == id }) {
                data.clients[index].defaults = calibrated
            }
        }) { dismiss() }
    }
}
