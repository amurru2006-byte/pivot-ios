import SwiftUI
import UIKit

/// Everything can be reviewed without changing an event. Using an estimate
/// merely returns it to the caller; saving the activity remains a separate act.
struct TravelCalculatorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: PivotStore
    @EnvironmentObject private var calendar: CalendarService
    @ObservedObject private var maps = AppleMapsService.shared
    @State private var originText: String
    @State private var destinationText: String
    @State private var origin: TravelPlace?
    @State private var destination: TravelPlace?
    @State private var mode: ClientTravelMode
    @State private var timing: TravelTiming
    @State private var date: Date
    @State private var originResults: [TravelPlace] = []
    @State private var destinationResults: [TravelPlace] = []
    @State private var result: TravelEstimate?
    @State private var message: String?
    @State private var task: Task<Void, Never>?
    private let nextStart: Date?
    private let context: TravelEventContext?
    private let onUse: ((TravelEstimate) -> Void)?

    init(origin: String = "", destination: String = "", mode: ClientTravelMode = .transit,
         date: Date = Date().addingTimeInterval(300), timing: TravelTiming = .departAt,
         nextStart: Date? = nil, context: TravelEventContext? = nil, onUse: ((TravelEstimate) -> Void)? = nil) {
        _originText = State(initialValue: origin); _destinationText = State(initialValue: destination)
        _mode = State(initialValue: TravelRouteRequest.supportedModes.contains(mode) ? mode : .transit)
        _date = State(initialValue: date); _timing = State(initialValue: timing)
        self.nextStart = nextStart; self.context = context; self.onUse = onUse
    }
    private var request: TravelRouteRequest? {
        guard let origin, let destination else { return nil }
        return .init(origin: origin, destination: destination, mode: mode, timing: timing, date: date)
    }
    var body: some View {
        PivotScreen {
            PivotHeader(title: "Il tempo per arrivare", subtitle: "Scegli i luoghi e confronta i mezzi, senza uscire da Pivot.")
            privacyCard
            if maps.consentGranted {
                PivotCard {
                    placeField(isOrigin: true)
                    placeField(isOrigin: false)
                    Picker("Mezzo", selection: $mode) {
                        ForEach(TravelRouteRequest.supportedModes, id: \.self) { Text($0.label).tag($0) }
                    }.accessibilityIdentifier("travel-mode")
                    Picker("Orario", selection: $timing) {
                        ForEach(TravelTiming.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    DatePicker(timing.label, selection: $date).environment(\.locale, Locale(identifier: "it_IT"))
                    Button("Calcola con Apple Maps") { calculate() }.buttonStyle(PivotPrimaryButton())
                        .disabled(request == nil || maps.busy).accessibilityIdentifier("travel-calculate")
                    if maps.busy { ProgressView("Richiesta ad Apple Maps…") }
                }
                if let result { resultCard(result) }
            }
            if let message { Text(message).font(.subheadline).foregroundStyle(PivotTheme.amber).accessibilityIdentifier("travel-message") }
            if maps.synthetic {
                Text("Richieste sintetiche: \(maps.requestCount)").font(.caption).accessibilityIdentifier("travel-test-count")
            }
        }.navigationTitle("Tragitti")
            .onChange(of: originText) { _, _ in origin = nil; originResults = []; invalidate() }
            .onChange(of: destinationText) { _, _ in destination = nil; destinationResults = []; invalidate() }
            .onChange(of: mode) { _, _ in invalidate() }
            .onChange(of: timing) { _, _ in invalidate() }
            .onChange(of: date) { _, _ in invalidate() }
            .onChange(of: maps.consentGranted) { _, allowed in if !allowed { invalidate(); originResults = []; destinationResults = [] } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { invalidate() } }
            .onChange(of: calendar.events) { _, _ in checkContext() }
            .onChange(of: store.data.updatedAt) { _, _ in checkContext() }
            .onDisappear { task?.cancel(); maps.cancelPending() }
    }
    private var privacyCard: some View {
        PivotCard {
            Label("Apple Maps, solo con il tuo consenso", systemImage: "hand.raised.fill").font(.headline)
            Text("La ricerca invia ad Apple il luogo che scrivi. Il calcolo invia i due luoghi scelti, il mezzo e l’orario. Nessuna posizione GPS continua, dato Salute, nota o indirizzo viene aggiunto all’AI online.")
                .font(.caption).foregroundStyle(PivotTheme.muted)
            Text("Le richieste sono avviate da te. Il consenso non è incluso nei backup esportati da Pivot. La revoca blocca le richieste successive e annulla l’attesa, ma non ritira dati già inviati.")
                .font(.caption).foregroundStyle(PivotTheme.muted)
            if maps.consentGranted {
                Button("Revoca consenso Apple Maps", role: .destructive) { maps.setConsent(false) }
                    .frame(minHeight: 44).accessibilityIdentifier("travel-revoke")
            } else {
                Button("Autorizzo le richieste ad Apple Maps") { maps.setConsent(true) }.buttonStyle(PivotPrimaryButton())
                    .accessibilityIdentifier("travel-consent")
                Text("Senza consenso puoi continuare a usare i tempi verificati manualmente.").font(.caption).foregroundStyle(PivotTheme.muted)
            }
        }
    }
    @ViewBuilder private func placeField(isOrigin: Bool) -> some View {
        let chosen = isOrigin ? origin : destination
        let results = isOrigin ? originResults : destinationResults
        TextField(isOrigin ? "Luogo di partenza" : "Destinazione", text: isOrigin ? $originText : $destinationText)
            .textInputAutocapitalization(.words).autocorrectionDisabled()
            .accessibilityIdentifier(isOrigin ? "travel-origin" : "travel-destination")
        if let chosen {
            Label("\(chosen.name) · \(chosen.address)", systemImage: "checkmark.circle").font(.caption).foregroundStyle(PivotTheme.accent)
        }
        Button(isOrigin ? "Cerca partenza" : "Cerca destinazione") { search(isOrigin: isOrigin) }
            .frame(minHeight: 44).disabled(maps.busy).accessibilityIdentifier(isOrigin ? "travel-search-origin" : "travel-search-destination")
        ForEach(results) { place in
            Button {
                if isOrigin { origin = place; originResults = [] } else { destination = place; destinationResults = [] }
                result = nil; message = nil
            } label: {
                VStack(alignment: .leading) { Text(place.name); Text(place.address).font(.caption).foregroundStyle(PivotTheme.muted) }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.accessibilityIdentifier("travel-place-\(isOrigin ? "origin" : "destination")-\(place.name)")
        }
    }
    private func resultCard(_ value: TravelEstimate) -> some View {
        PivotCard(tint: PivotTheme.blue) {
            Label("\(value.minutes.map(String.init) ?? "—") min · \(value.request.mode.label)", systemImage: "map").font(.headline)
                .accessibilityIdentifier("travel-result")
            Text("Partenza \(PivotDate.time(value.departure)) · arrivo \(PivotDate.time(value.arrival))").font(.subheadline)
            Text("Apple Maps · richiesta delle \(PivotDate.time(value.fetchedAt))").font(.caption).foregroundStyle(PivotTheme.muted)
            if let nextStart, let conflict = value.conflicts(nextStart: nextStart) {
                Label(conflict ? "L’arrivo stimato supera l’inizio dell’impegno successivo." : "L’arrivo stimato precede l’impegno successivo.",
                      systemImage: conflict ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.subheadline).foregroundStyle(conflict ? PivotTheme.amber : PivotTheme.accent)
            }
            Text("È una stima, non una garanzia. Cambio, doccia e margine non sono inclusi. Per i mezzi pubblici non mostra coincidenze, scioperi o soppressioni: verifica il servizio prima di partire.")
                .font(.caption).foregroundStyle(PivotTheme.muted)
            if let onUse {
                Button("Usa questa stima") {
                    guard contextIsCurrent, let request, value.isUsable(for: request, consent: maps.consentGranted, now: Date()) else {
                        message = "La stima è scaduta o i dati sono cambiati. Ricalcola il tragitto."; return
                    }
                    onUse(value); dismiss()
                }.buttonStyle(PivotPrimaryButton()).accessibilityIdentifier("travel-use")
            }
        }
    }
    private func invalidate() { task?.cancel(); maps.cancelPending(); result = nil; message = nil }
    private var contextIsCurrent: Bool {
        guard let context else { return true }
        return calendar.hasAccess && context.isCurrent(events: calendar.events, data: store.data)
    }
    private func checkContext() {
        if !contextIsCurrent { invalidate(); message = "Il Calendario è cambiato. Riapri il tragitto dall’attività aggiornata." }
    }
    private func search(isOrigin: Bool) {
        guard contextIsCurrent else { checkContext(); return }
        let text = isOrigin ? originText : destinationText
        message = nil; result = nil
        task = Task { @MainActor in
            do {
                let places = try await maps.places(matching: text)
                guard !Task.isCancelled else { return }
                if isOrigin { originResults = places } else { destinationResults = places }
            } catch { if !Task.isCancelled { message = error.localizedDescription } }
        }
    }
    private func calculate() {
        guard contextIsCurrent else { checkContext(); return }
        guard let request else { return }
        message = nil; result = nil
        task = Task { @MainActor in
            do { let value = try await maps.estimate(request); if !Task.isCancelled { result = value } }
            catch { if !Task.isCancelled { message = error.localizedDescription } }
        }
    }
}
