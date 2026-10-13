import SwiftUI

struct TrainingRepProgressionCard: View {
    let exercise: TrainingExercise
    let result: TrainingRepProgression
    var body: some View {
        PivotCard {
            Text("Obiettivo e andamento").font(.headline)
            Text("Obiettivo attuale: \(exercise.sets) serie × \(exercise.reps)").font(.subheadline)
            if result.activeConcernCount > 0 {
                NavigationLink { TrainingConcernsView() } label: {
                    Label("\(result.activeConcernCount) segnalazioni da tenere presenti · apri", systemImage: "exclamationmark.triangle")
                }.buttonStyle(PivotSecondaryButton()).accessibilityIdentifier("progression-concerns")
                Text("Il risultato numerico non valuta il fastidio e non dà un via libera ad aumentare.")
                    .font(.caption).foregroundStyle(PivotTheme.amber)
            }
            if let last = result.latest {
                Text(last.status.title).font(.subheadline.weight(.semibold)).accessibilityIdentifier("progression-status")
                Text("\(PivotDate.shortDate(last.date)) · fase: \(last.phase?.label ?? "non dichiarata")")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
                if last.target != exercise.reps || last.prescribedCount != exercise.sets {
                    Text("Questo risultato usa l'obiettivo registrato allora: \(last.prescribedCount) serie × \(last.target)").font(.caption)
                }
                if last.range != nil {
                    Text("\(last.completedCount) di \(last.prescribedCount) serie prescritte confermate")
                        .font(.subheadline).accessibilityIdentifier("progression-completed")
                    if let range = last.range, last.status != .uninterpreted {
                        Text("\(last.upperCount) di \(last.prescribedCount) serie con almeno \(range.upper) ripetizioni")
                            .font(.caption).foregroundStyle(PivotTheme.muted)
                    }
                }
                if let comparison = result.comparison {
                    let delta = comparison.repDelta
                    Text("Stessa prescrizione e stessi carichi: \(delta > 0 ? "+" : "")\(delta) ripetizioni totali rispetto al \(PivotDate.shortDate(comparison.previousDate)).")
                        .font(.subheadline).accessibilityIdentifier("progression-comparison")
                } else {
                    Text("Nessuna sessione precedente confrontabile.")
                        .font(.caption).foregroundStyle(PivotTheme.muted)
                }
                if last.phase == .deload || last.phase == .returning {
                    Text("Scarico o rientro: mostro il lavoro registrato, senza suggerire aumenti.")
                        .font(.caption).foregroundStyle(PivotTheme.amber)
                }
            } else {
                Text("Nessuna sessione per questa esatta variante. I valori precompilati non sono risultati.")
                    .font(.subheadline).foregroundStyle(PivotTheme.muted)
            }
            Text("Carichi manuali · nessun aumento automatico.")
                .font(.caption).foregroundStyle(PivotTheme.muted)
            DisclosureGroup("Come leggo questi dati") {
                Text("Conto solo le serie prescritte e confermate, non warm-up o extra. Non interpreto isometrie, istruzioni per lato, piramidi o AMRAP come rep range. Per il confronto servono una sessione precedente conclusa e completa con stessa variante, obiettivo, serie, tipo, indicazioni PT, recuperi prescritti, fase e carichi registrati. Recuperi effettivi, tecnica e sensazioni possono differire; la fase non dichiarata resta sconosciuta. Un confronto numerico non dimostra uno stallo o la sicurezza di un aumento. Raggiungere le ripetizioni non autorizza un aumento; non c'è una regola automatica impostata.")
                    .font(.caption).foregroundStyle(PivotTheme.muted)
            }.font(.subheadline)
        }.accessibilityElement(children: .contain)
    }
}
