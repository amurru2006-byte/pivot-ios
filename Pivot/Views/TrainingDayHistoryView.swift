import SwiftUI

struct TrainingDayHistoryView: View {
    @EnvironmentObject var store: PivotStore
    let planID: UUID
    let dayID: String?
    let dayName: String
    @State private var deleting: TrainingSession?
    @State private var busy = false
    @State private var message: String?
    private var library: TrainingLibrary { store.data.training ?? TrainingLibrary() }
    private var sessions: [TrainingSession] {
        TrainingHistory.sessions(planID: planID, dayID: dayID, dayName: dayName, library: library)
    }
    var body: some View {
        PivotScreen {
            PivotHeader(title: "Cronologia · \(dayName)", subtitle: "Gli allenamenti di questa giornata, dal più recente.")
            Text("Apri un allenamento per correggere serie, carichi, note e orari. Non cambia la scheda del personal. Eliminando una sessione, progressi e rank usano solo i dati rimasti.")
                .font(.subheadline).foregroundStyle(PivotTheme.muted)
            if sessions.isEmpty {
                EmptyCard(title: "Nessun allenamento salvato", message: "Qui compariranno le sessioni di questa giornata quando inizi ad allenarti.", icon: "clock.arrow.circlepath")
                    .accessibilityIdentifier("workout-history-empty")
            }
            LazyVStack(alignment: .leading, spacing: 22) {
            ForEach(sessions) { session in
                PivotCard {
                    Text("\(PivotDate.shortDate(session.start)) · \(PivotDate.time(session.start))").font(.headline)
                    Text("\(session.end.map { "Terminato alle " + PivotDate.time($0) } ?? "In corso") · \(TrainingHistory.performedSets(session)) serie svolte")
                        .font(.subheadline).foregroundStyle(PivotTheme.muted)
                    Text("Fase: \(session.phase?.label ?? "non dichiarata")").font(.caption).foregroundStyle(PivotTheme.muted)
                    NavigationLink {
                        TrainingSessionView(session: session, tips: library.tips,
                            event: session.calendarEventID.flatMap { store.data.records[$0]?.snapshot }, historicalEdit: true)
                    } label: {
                        Label("Apri e modifica", systemImage: "pencil")
                    }.buttonStyle(PivotSecondaryButton())
                        .accessibilityLabel("Apri e modifica allenamento del \(PivotDate.shortDate(session.start)) alle \(PivotDate.time(session.start))")
                        .accessibilityIdentifier("history-open-\(session.id.uuidString)")
                    Button("Elimina allenamento", role: .destructive) { deleting = session }
                        .frame(minHeight: 44)
                        .accessibilityLabel("Elimina allenamento del \(PivotDate.shortDate(session.start)) alle \(PivotDate.time(session.start))")
                        .accessibilityIdentifier("history-delete-\(session.id.uuidString)")
                }.accessibilityElement(children: .contain)
            }
            }
            if busy { ProgressView("Elimino e salvo…") }
            if let message { Text(message).foregroundStyle(PivotTheme.amber).accessibilityIdentifier("history-message") }
        }.navigationTitle("Cronologia")
            .disabled(busy || store.locked || store.isRestoring)
            .alert("Eliminare questo allenamento?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Annulla", role: .cancel) { deleting = nil }
                Button("Elimina definitivamente", role: .destructive) {
                    guard let expected = deleting else { return }
                    deleting = nil; busy = true
                    Task {
                        defer { busy = false }
                        do { message = try await store.deleteTraining(expected) }
                        catch { message = error.localizedDescription }
                    }
                }
            } message: {
                Text(deleting.map { session in
                    let work = TrainingHistory.performedSets(session)
                    return work > 0
                        ? "Questo allenamento contiene \(work) serie svolte: verranno eliminate insieme alle note. Progressi e rank saranno ricalcolati. La scheda e l’evento nel Calendario restano. Questa operazione non si annulla."
                        : "Rimuove questa sessione avviata senza serie svolte. La scheda e l’evento nel Calendario restano. Questa operazione non si annulla."
                } ?? "")
            }
    }
}
