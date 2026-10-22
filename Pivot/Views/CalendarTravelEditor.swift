import SwiftUI

/// Native grouped rows, like Calendar. Closing this sheet never writes an event.
struct CalendarTravelEditor: View {
    @Environment(\.dismiss) private var dismiss
    let start: Date?
    let suggestedOrigin: String
    let onSave: (CalendarCreationOptions) -> Void
    @State var options: CalendarCreationOptions
    @State private var minutes: Int
    @State private var origin: String
    @State private var estimate: TravelEstimate?
    @State private var problem: String?
    @State private var choosingOrigin = false
    @State private var choosingDestination = false
    @State private var separateEvent: Bool
    @FocusState private var editingOrigin: Bool

    init(options: CalendarCreationOptions, start: Date?, suggestedOrigin: String,
         onSave: @escaping (CalendarCreationOptions) -> Void) {
        _options = State(initialValue: options); self.start = start
        self.suggestedOrigin = suggestedOrigin; self.onSave = onSave
        _minutes = State(initialValue: options.plannedTravel?.minutes ?? 0)
        _origin = State(initialValue: options.plannedTravel?.origin ?? suggestedOrigin)
        _estimate = State(initialValue: options.plannedTravel?.estimate)
        _separateEvent = State(initialValue: options.travel != nil)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Stima basata sulla posizione") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Posizione di partenza")
                        TextField("Indirizzo o luogo", text: $origin)
                            .font(.subheadline).foregroundStyle(.secondary)
                            .focused($editingOrigin).textInputAutocapitalization(.words).autocorrectionDisabled()
                            .accessibilityLabel("Posizione di partenza").accessibilityIdentifier("creation-travel-origin")
                    }
                    Button { choosingOrigin = true } label: { Label("Scegli partenza salvata", systemImage: "bookmark") }
                        .accessibilityIdentifier("creation-travel-saved-origin")
                    LabeledContent("Destinazione", value: options.location.isEmpty ? "Da scegliere nell’evento" : options.location)
                    Button { choosingDestination = true } label: { Label("Scegli destinazione salvata", systemImage: "bookmark") }
                        .accessibilityIdentifier("creation-travel-saved-destination")
                    if let start, start >= Date() {
                        NavigationLink {
                            TravelCalculatorView(origin: origin, destination: options.location, date: start, timing: .arriveBy) { value in
                                guard let valueMinutes = value.minutes else { return }
                                guard value.request.timing == .arriveBy, value.request.date == start else {
                                    problem = "Scegli «Arriva entro» all’orario di inizio dell’attività, poi ricalcola."; return
                                }
                                options.location = value.request.destination.address
                                origin = value.request.origin.address; minutes = valueMinutes; estimate = value
                                problem = nil
                            }
                        } label: { Label("Calcola con Apple Maps", systemImage: "map") }
                            .accessibilityIdentifier("creation-travel-maps")
                    } else {
                        Text("Per un evento passato indica il tempo effettivo: Maps non ricostruisce il viaggio di allora.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let estimate {
                        Label("\(estimate.minutes ?? 0) min · \(estimate.request.mode.label)", systemImage: "checkmark.circle")
                            .foregroundStyle(PivotTheme.accent).accessibilityIdentifier("creation-travel-estimate")
                    }
                }
                Section {
                    Toggle("Crea uno Spostamento separato", isOn: $separateEvent)
                        .accessibilityIdentifier("creation-travel-separate")
                    ForEach(Array(Set([0, 5, 15, 30, 60, 90, 120, minutes])).sorted(), id: \.self) { value in
                        Button {
                            editingOrigin = false; minutes = value; estimate = nil
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: minutes == value && estimate == nil ? "checkmark" : "circle")
                                    .foregroundStyle(minutes == value ? PivotTheme.accent : .clear).frame(width: 20)
                                Text(value == 0 ? "Nessuno" : duration(value)).foregroundStyle(PivotTheme.text)
                                Spacer()
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("creation-travel-minutes-\(value)")
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    DurationField(title: "Altro tempo", seconds: Binding(get: { minutes * 60 }, set: {
                        minutes = max(0, ($0 ?? 0) / 60); estimate = nil
                    }), maxHours: 24)
                } footer: {
                    Text(separateEvent
                        ? "«Spostamento» sarà un secondo evento nello stesso calendario. Partenza e destinazione saranno visibili a chi può leggerlo."
                        : "Pivot creerà solo l’attività. Aprila poi in Calendario Apple → Modifica → Tempo di percorrenza per impostare la fascia nativa. Questa stima serve ai controlli di Pivot, ma non scrive né legge quel campo Apple.")
                }
                if let problem { Section { Text(problem).foregroundStyle(PivotTheme.amber) } }
            }.navigationTitle("Tempo di percorrenza").navigationBarTitleDisplayMode(.inline)
                .tint(PivotTheme.accent)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Annulla")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button { finish() } label: { Image(systemName: "checkmark") }.accessibilityLabel("Conferma tempo di percorrenza")
                            .accessibilityIdentifier("creation-travel-done")
                    }
                }.pivotKeyboardToolbar(identifier: "creation-travel-keyboard-done") { editingOrigin = false }
                .onChange(of: origin) { _, text in
                    if let estimate, text != estimate.request.origin.address { self.estimate = nil }
                }
                .sheet(isPresented: $choosingOrigin) {
                    NavigationStack { SavedPlacesView { place in
                        origin = place.address; estimate = nil; minutes = 0; problem = nil
                    } }
                }
                .sheet(isPresented: $choosingDestination) {
                    NavigationStack { SavedPlacesView { place in
                        options.location = place.address; estimate = nil; minutes = 0; problem = nil
                    } }
                }
        }
    }
    private func duration(_ value: Int) -> String {
        value < 60 ? "\(value) min" : (value % 60 == 0 ? "\(value / 60) h" : "\(value / 60) h \(value % 60) min")
    }
    private func finish() {
        var result = options
        result.travel = nil; result.appleCalendarTravel = nil
        if minutes > 0 {
            let travel = CalendarCreationTravel(minutes: minutes, origin: origin, estimate: estimate)
            if separateEvent { result.travel = travel } else { result.appleCalendarTravel = travel }
        }
        guard result.isValid, minutes == 0 || (!origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !result.location.isEmpty) else {
            problem = "Indica partenza e destinazione prima di confermare il viaggio."; return
        }
        onSave(result); dismiss()
    }
}

struct CalendarCreationPreview: View {
    let draft: CoachCalendarDraft
    let options: CalendarCreationOptions
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let start = draft.start, let travel = options.plannedTravel {
                let departure = travel.estimate?.departure ?? start.addingTimeInterval(-Double(travel.minutes) * 60)
                let day = PivotDate.calendar.isDate(departure, inSameDayAs: start) ? "" : PivotDate.shortDate(departure) + " "
                Label("Spostamento · \(day)\(PivotDate.time(departure)) – \(PivotDate.time(start))",
                      systemImage: travel.symbolName)
                    .font(.subheadline).accessibilityIdentifier("creation-travel-preview")
                Divider()
                if options.appleCalendarTravel != nil {
                    Text("Percorrenza Apple da completare in Calendario").font(.caption)
                        .accessibilityIdentifier("creation-apple-travel-manual")
                }
            }
            Text(draft.title.isEmpty ? "Nuovo impegno" : draft.title).font(.headline)
            if let start = draft.start, let end = draft.end {
                let finalDay = PivotDate.calendar.isDate(start, inSameDayAs: end) ? "" : PivotDate.shortDate(end) + " "
                Label("\(PivotDate.shortDate(start)) · \(PivotDate.time(start)) – \(finalDay)\(PivotDate.time(end))", systemImage: "clock")
                    .font(.subheadline).accessibilityIdentifier("creation-time-summary")
            }
            if !options.location.isEmpty { Label(options.location, systemImage: "mappin.and.ellipse").font(.subheadline) }
        }.foregroundStyle(color).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
            .accessibilityElement(children: .contain)
    }
}
