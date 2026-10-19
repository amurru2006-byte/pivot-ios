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
    @FocusState private var editingOrigin: Bool

    init(options: CalendarCreationOptions, start: Date?, suggestedOrigin: String,
         onSave: @escaping (CalendarCreationOptions) -> Void) {
        _options = State(initialValue: options); self.start = start
        self.suggestedOrigin = suggestedOrigin; self.onSave = onSave
        _minutes = State(initialValue: options.travel?.minutes ?? 0)
        _origin = State(initialValue: options.travel?.origin ?? suggestedOrigin)
        _estimate = State(initialValue: options.travel?.estimate)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Stima basata sulla posizione") {
                    TextField("Posizione di partenza", text: $origin)
                        .focused($editingOrigin).textInputAutocapitalization(.words)
                        .accessibilityIdentifier("creation-travel-origin")
                    LabeledContent("Destinazione", value: options.location.isEmpty ? "Da scegliere nell’evento" : options.location)
                    if let start, start >= Date() {
                        NavigationLink {
                            TravelCalculatorView(origin: origin, destination: options.location, date: start, timing: .arriveBy) { value in
                                guard let valueMinutes = value.minutes else { return }
                                options.location = value.request.destination.address
                                origin = value.request.origin.address; minutes = valueMinutes; estimate = value
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
                    ForEach([0, 5, 15, 30, 60, 90, 120], id: \.self) { value in
                        Button {
                            editingOrigin = false; minutes = value; estimate = nil
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: minutes == value && estimate == nil ? "checkmark" : "circle")
                                    .foregroundStyle(minutes == value ? PivotTheme.accent : .clear).frame(width: 20)
                                Text(value == 0 ? "Nessuno" : duration(value)).foregroundStyle(.primary)
                                Spacer()
                            }.frame(minHeight: 36)
                        }.accessibilityIdentifier("creation-travel-minutes-\(value)")
                    }
                    DurationField(title: "Altro tempo", seconds: Binding(get: { minutes * 60 }, set: {
                        minutes = max(0, ($0 ?? 0) / 60); estimate = nil
                    }), maxHours: 24)
                } footer: {
                    Text("Il viaggio sarà un evento separato «Spostamento», nello stesso calendario. Non cambia la durata dell’attività e non conta come lezione o allenamento.")
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
        }
    }
    private func duration(_ value: Int) -> String {
        value < 60 ? "\(value) min" : (value % 60 == 0 ? "\(value / 60) h" : "\(value / 60) h \(value % 60) min")
    }
    private func finish() {
        var result = options
        result.travel = minutes == 0 ? nil : .init(minutes: minutes, origin: origin, estimate: estimate)
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
            if let start = draft.start, let travel = options.travel {
                Label("Spostamento · \(PivotDate.time(travel.estimate?.departure ?? start.addingTimeInterval(-Double(travel.minutes) * 60))) – \(PivotDate.time(start))",
                      systemImage: "figure.walk")
                    .font(.subheadline).accessibilityIdentifier("creation-travel-preview")
                Divider()
            }
            Text(draft.title.isEmpty ? "Nuovo impegno" : draft.title).font(.headline)
            if let start = draft.start, let end = draft.end {
                Label("\(PivotDate.shortDate(start)) · \(PivotDate.time(start)) – \(PivotDate.time(end))", systemImage: "clock")
                    .font(.subheadline)
            }
            if !options.location.isEmpty { Label(options.location, systemImage: "mappin.and.ellipse").font(.subheadline) }
        }.foregroundStyle(color).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
            .accessibilityElement(children: .contain)
    }
}
