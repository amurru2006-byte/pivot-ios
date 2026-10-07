import SwiftUI
struct ExerciseTechniqueCard: View {
    let exercise: TrainingExercise
    let catalog: CatalogExercise?
    var body: some View {
        PivotCard {
            Text("Esecuzione e controlli tecnici").font(.headline)
            if let guide = ExerciseTechnique.forExercise(exercise, catalog: catalog) {
                ForEach(Array(guide.execution.enumerated()), id: \.offset) { step in Text("\(step.offset + 1). \(step.element)").font(.subheadline) }
                Text("Errori comuni").font(.subheadline.bold()).padding(.top, 6)
                ForEach(guide.mistakes, id: \.self) { Text("• " + $0).font(.caption).foregroundStyle(PivotTheme.amber) }
            } else {
                Text("Per questa variante non c'è ancora una spiegazione specifica verificata in italiano. Scegli l'associazione esatta e usa le indicazioni del PT; non sostituisco la tecnica di un altro esercizio.").font(.subheadline)
                Text("Controlli generali: attrezzatura stabile, regolazioni annotate, movimento controllato e convenzione del carico sempre uguale.").font(.caption).foregroundStyle(PivotTheme.muted)
            }
            Text("Indicazioni generali, non una valutazione della tua tecnica. La variante, il carico e i recuperi restano quelli concordati con il PT.").font(.caption).foregroundStyle(PivotTheme.muted)
        }
    }
}
