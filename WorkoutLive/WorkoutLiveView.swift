import SwiftUI
import WidgetKit

/// Shared with visual QA. Adapt to rest/work instead of fitting every control
/// into tiny buttons; the default layout stays below the 160-point system cap.
struct WorkoutLiveView: View {
    let sessionID: String
    let state: WorkoutAttributes.ContentState
    private var resting: Bool { state.deadline != nil || state.pausedSeconds != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(resting ? "Recupero · " + (state.restExercise ?? state.exercise) : state.isDone ? "Serie registrate" : state.exercise)
                        .font(.system(size: 20, weight: .semibold)).lineLimit(1)
                    Text(resting ? (state.isDone ? "Ultimo recupero" : "Prossima · " + state.exercise) : state.status.isEmpty ? prescription : state.status)
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                }
                Spacer(minLength: 0)
                if !resting && !state.isDone { action("checkmark", label: "Conferma serie", value: "done") }
            }.frame(minHeight: 44)
            if resting {
                HStack(spacing: 6) {
                    if let end = state.deadline {
                        Text(timerInterval: Date()...max(Date(), end), countsDown: true)
                            .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(.yellow).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(duration(state.pausedSeconds ?? 0))
                            .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(.yellow).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    action(state.deadline == nil ? "play.fill" : "pause.fill", label: state.deadline == nil ? "Riprendi recupero" : "Pausa recupero", value: "pause")
                    action("arrow.counterclockwise", label: "Reset recupero", value: "reset")
                    action("forward.end.fill", label: state.isDone ? "Chiudi recupero" : "Inizia prossima serie", value: "next")
                }.frame(height: 48)
                Text(state.deadline == nil ? "In pausa" : state.isDone ? "Poi termina l’allenamento nell’app" : prescription)
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
            } else if !state.isDone {
                HStack(spacing: 8) {
                    // Bilateral holds: adjust the two sides. Optional weight
                    // stays readable below and can be edited in the app.
                    if state.isometric && state.separateSides {
                        metric("Sinistra", value: state.left.map { "\($0) s" } ?? "— s", minus: "left-", plus: "left+")
                        metric("Destra", value: state.right.map { "\($0) s" } ?? "— s", minus: "right-", plus: "right+")
                    } else {
                        if !state.isometric || state.weighted {
                            metric(state.isometric ? "Zavorra" : "Carico", value: state.kg.map { $0.formatted() + " kg" } ?? "— kg", minus: "kg-", plus: "kg+")
                        }
                        if state.isometric {
                            metric("Durata", value: state.seconds.map { "\($0) s" } ?? "— s", minus: "seconds-", plus: "seconds+")
                        } else { metric("Reps", value: state.reps.map(String.init) ?? "—", minus: "reps-", plus: "reps+") }
                    }
                }
                if state.isometric && state.separateSides && state.weighted {
                    Text("Zavorra \(state.kg.map { $0.formatted() + " kg" } ?? "— kg") · modifica nell’app")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                }
            } else {
                Text("Apri Pivot per terminare e salvare l’allenamento")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10).foregroundStyle(.white)
        .widgetURL(URL(string: "pivot://workout/\(sessionID)?set=\(state.setID)"))
    }
    private var prescription: String {
        let current = state.kind == "Warm-up" ? "Warm-up \(state.number)" : "Serie \(state.workingNumber ?? state.number)"
        guard let sets = state.targetSets, let reps = state.targetReps else { return current }
        return "\(current) di \(sets) · \(reps)\(state.isometric ? "" : " reps")"
    }
    private func duration(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }
    private func metric(_ title: String, value: String, minus: String, plus: String) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.8))
            HStack(spacing: 0) {
                action("minus", label: "Riduci \(title)", value: minus)
                Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.75).frame(maxWidth: .infinity)
                action("plus", label: "Aumenta \(title)", value: plus)
            }
        }.frame(maxWidth: .infinity)
    }
    private func action(_ icon: String, label: String, value: String) -> some View {
        Button(intent: WorkoutActionIntent(sessionID: sessionID, setID: state.setID, action: value)) {
            Image(systemName: icon).font(.system(size: 19, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).foregroundStyle(.mint).accessibilityLabel(label)
    }
}
