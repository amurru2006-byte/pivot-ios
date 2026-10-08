import SwiftUI

/// Visual QA uses exactly the view compiled into the extension. This preview
/// is not a claim that the simulator reproduces system Lock Screen behavior.
struct WorkoutWidgetPreview: View {
    private func state(_ exercise: String, iso: Bool = false, sides: Bool = false, weighted: Bool = false) -> WorkoutAttributes.ContentState {
        .init(exercise: exercise, setID: "preview", number: 2, kind: "Working", kg: 70, reps: 6,
              seconds: 30, left: 25, right: 30, isometric: iso, weighted: weighted, separateSides: sides,
              deadline: nil, pausedSeconds: nil, status: "", isDone: false, targetSets: 3,
              targetReps: iso ? "30 s per lato" : "4–6", workingNumber: 1)
    }
    var body: some View {
        VStack(spacing: 16) {
            Text("Anteprima layout Live Activity").font(.headline)
            WorkoutLiveView(sessionID: "preview", state: state("Bench Press"))
                .background(.black, in: RoundedRectangle(cornerRadius: 20))
            WorkoutLiveView(sessionID: "preview", state: state("Copenhagen Plank", iso: true, sides: true, weighted: true))
                .background(.black, in: RoundedRectangle(cornerRadius: 20))
            Text("Dati sintetici · prova sul blocco schermo ancora necessaria").font(.caption).foregroundStyle(PivotTheme.muted)
            Spacer()
        }.padding(16)
    }
}
