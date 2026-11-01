import SwiftUI

struct PerformanceView: View {
    @EnvironmentObject private var store: PivotStore
    @EnvironmentObject private var diagnostics: PerformanceDiagnostics
    @EnvironmentObject private var coachModel: LocalCoachService
    var body: some View {
        PivotCard {
            Text(store.saveStatus).accessibilityIdentifier("storage-status")
            Button("Riprova / completa salvataggio") { Task { await store.flushPendingWrites() } }
                .buttonStyle(PivotSecondaryButton()).disabled(store.isLoading || store.locked)
        }
        PivotCard {
            Text("Tempi dell’ultima operazione").font(.headline)
            ForEach(diagnostics.entries) { entry in
                HStack {
                    Text(entry.name)
                    Spacer()
                    Text(String(format: "%.2f s · %d volte", entry.seconds, entry.count)).font(.caption.monospacedDigit())
                }
            }
            Text("Questa schermata registra soltanto tempi e contatori, senza contenuti personali.").font(.caption).foregroundStyle(PivotTheme.muted)
        }
        PivotCard {
            Text(coachModel.memoryStatus).font(.subheadline)
            Button("Metti in pausa AI e libera memoria") { coachModel.pauseAndUnload() }.buttonStyle(PivotSecondaryButton())
            if let report = coachModel.performanceReport { Text(report).font(.caption).foregroundStyle(PivotTheme.muted) }
        }
    }
}
