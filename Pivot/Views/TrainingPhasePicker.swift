import SwiftUI

struct TrainingPhasePicker: View {
    @Binding var phase: TrainingPhase?
    var title = "Fase"
    var inheritanceLabel: String? = nil
    var body: some View {
        Picker(title, selection: $phase) {
            Text(inheritanceLabel ?? "Non dichiarata").tag(Optional<TrainingPhase>.none)
            ForEach(TrainingPhase.allCases) { value in Text(value.label).tag(Optional(value)) }
        }.pickerStyle(.menu)
    }
}
