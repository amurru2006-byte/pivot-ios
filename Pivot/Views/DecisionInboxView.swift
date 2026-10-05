import SwiftUI

struct DecisionInboxView: View {
    @EnvironmentObject var store: PivotStore
    @EnvironmentObject var calendar: CalendarService
    @Environment(\.dismiss) private var dismiss
    var initialID: String? = nil
    @State private var travelTimes: [String: Int] = [:]
    private var decisions: [EventDecision] { store.data.decisions ?? [] }
    var body: some View {
        NavigationStack {
            PivotScreen {
                PivotHeader(title: "Da decidere", subtitle: "Una domanda alla volta. Puoi tornare qui quando vuoi.")
                if decisions.isEmpty {
                    EmptyCard(title: "Tutto chiarito", message: "Nessun dubbio da risolvere nella prossima settimana.", icon: "checkmark.circle")
                }
                ForEach(decisions.sorted { lhs, rhs in
                    if lhs.id == rhs.id { return false }
                    if lhs.id == initialID { return true }
                    if rhs.id == initialID { return false }
                    return lhs.date < rhs.date
                }) { decision in
                    card(decision)
                }
            }
            .navigationTitle("Pivot")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Più tardi") { deferQuestion(); dismiss() } } }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
        .onDisappear { deferQuestion() }
    }
    private func card(_ decision: EventDecision) -> some View {
        PivotCard(tint: decision.relation == .uncertain ? PivotTheme.blue : PivotTheme.amber) {
            Label(decision.relation == .uncertain ? "Una cosa da chiarire" : "Serve una modifica", systemImage: decision.relation == .uncertain ? "questionmark.bubble" : "calendar.badge.exclamationmark").font(.headline)
            Text(decision.explanation).font(.subheadline)
            ForEach([decision.firstID, decision.secondID], id: \.self) { id in
                if let item = Planner.plannedEvents(calendar.events, data: store.data).first(where: { $0.id == id }) {
                    NavigationLink { EventDetailView(event: item, initial: store.record(for: item), rule: store.rule(for: item)) } label: {
                        HStack {
                            Circle().fill(Color(calendarItem: item)).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).font(.subheadline.weight(.semibold))
                                Text(item.timeSummary).font(.caption).foregroundStyle(PivotTheme.muted)
                            }
                            Spacer(); Image(systemName: "chevron.right").font(.caption)
                        }
                    }.buttonStyle(.plain)
                }
            }
            if decision.relation == .uncertain {
                if decision.explanation.contains("tragitto") {
                    DurationField(title: "Tragitto tra questi due impegni", seconds: Binding(get: { travelTimes[decision.id] }, set: { travelTimes[decision.id] = $0 }), maxHours: 8)
                    Button("Conferma questo tempo") { answer(decision, compatible: false, travel: travelTimes[decision.id].map { ($0 + 59) / 60 }) }
                        .buttonStyle(PivotPrimaryButton()).disabled(travelTimes[decision.id] == nil || store.locked)
                    Button("Controlla in Mappe") { openMaps(decision) }.buttonStyle(PivotSecondaryButton())
                } else {
                    Button("Sì, li faccio insieme") { answer(decision, compatible: true) }.buttonStyle(PivotPrimaryButton()).disabled(store.locked)
                    Button("No, sono impegni separati") { answer(decision, compatible: false) }.buttonStyle(PivotSecondaryButton()).disabled(store.locked)
                }
            } else {
                NavigationLink { CoachView() } label: { Label("Trova una soluzione con Pivot", systemImage: "arrow.triangle.branch") }.buttonStyle(PivotSecondaryButton())
                Text("Nessuna modifica al Calendario senza la tua conferma.").font(.caption).foregroundStyle(PivotTheme.muted)
            }
        }.id(decision.id)
    }
    private func answer(_ decision: EventDecision, compatible: Bool, travel: Int? = nil) {
        if store.change({ data in
            var answers = data.contextAnswers ?? []
            answers.removeAll { $0.id == decision.id }
            answers.append(.init(id: decision.id, compatible: compatible, answeredAt: Date(), travelMinutes: travel))
            data.contextAnswers = Array(answers.suffix(500))
            data.decisions = EventContext.refreshed(events: calendar.events, data: data, now: Date())
            var coach = data.coachState
            coach.messages.append(.init(dayKey: PivotDate.key(Date()), role: .system, text: "\(decision.firstTitle) / \(decision.secondTitle): " + (travel.map { "tragitto confermato \($0) min." } ?? (compatible ? "compatibili, confermato da te." : "impegni separati, da riorganizzare."))))
            data.coachState = coach
        }) { travelTimes.removeValue(forKey: decision.id); if initialID != nil { dismiss() } }
    }
    private func deferQuestion() {
        guard let initialID, store.data.decisions?.contains(where: { $0.id == initialID && !$0.deferred }) == true else { return }
        store.change { data in
            if let index = data.decisions?.firstIndex(where: { $0.id == initialID }) { data.decisions?[index].deferred = true }
        }
    }
    private func openMaps(_ decision: EventDecision) {
        let items = Planner.plannedEvents(calendar.events, data: store.data)
        guard let a = items.first(where: { $0.id == decision.firstID }), let b = items.first(where: { $0.id == decision.secondID }) else { return }
        var url = URLComponents(string: "https://maps.apple.com/")!
        url.queryItems = [.init(name: "saddr", value: a.location), .init(name: "daddr", value: b.location), .init(name: "dirflg", value: "r")]
        if let url = url.url { UIApplication.shared.open(url) }
    }
}
