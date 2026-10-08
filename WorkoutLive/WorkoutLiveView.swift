import SwiftUI
import WidgetKit

/// Shared by the extension and the simulator preview, so visual checks use the
/// actual widget layout. Three rows fit the Lock Screen's 160-point allowance.
struct WorkoutLiveView: View {
    let sessionID: String
    let state: WorkoutAttributes.ContentState
    private var resting: Bool { state.deadline != nil || state.pausedSeconds != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 30, weight: .medium)).foregroundStyle(.mint).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.exercise).font(.system(size: 18, weight: .semibold)).lineLimit(1)
                    Text(prescription).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            if !state.isDone {
                HStack(spacing: 10) {
                    if !state.isometric || state.weighted {
                        metric(state.isometric ? "Zavorra" : "Carico", value: state.kg.map { $0.formatted() + " kg" } ?? "— kg", minus: "kg-", plus: "kg+")
                    }
                    if state.isometric {
                        if state.separateSides {
                            metric("Sinistra", value: state.left.map { "\($0) s" } ?? "— s", minus: "left-", plus: "left+")
                            metric("Destra", value: state.right.map { "\($0) s" } ?? "— s", minus: "right-", plus: "right+")
                        } else {
                            metric("Durata", value: state.seconds.map { "\($0) s" } ?? "— s", minus: "seconds-", plus: "seconds+")
                        }
                    } else { metric("Reps", value: state.reps.map(String.init) ?? "—", minus: "reps-", plus: "reps+") }
                }
            }
            HStack(spacing: 8) {
                if let end = state.deadline {
                    Image(systemName: "timer").foregroundStyle(.yellow)
                    Text(timerInterval: Date()...max(Date(), end), countsDown: true)
                        .font(.system(size: 22, weight: .semibold)).monospacedDigit().foregroundStyle(.yellow)
                        .frame(maxWidth: 84, alignment: .leading)
                    Spacer(minLength: 0)
                    action("pause.fill", label: "Pausa recupero", value: "pause")
                    action("arrow.counterclockwise", label: "Reset recupero", value: "reset")
                    action("forward.end.fill", label: "Inizia prossima serie", value: "next")
                } else if let seconds = state.pausedSeconds {
                    Text("Pausa · \(seconds) s").font(.system(size: 16, weight: .semibold)).monospacedDigit()
                    Spacer(minLength: 0)
                    action("play.fill", label: "Riprendi recupero", value: "pause")
                    action("arrow.counterclockwise", label: "Reset recupero", value: "reset")
                    action("forward.end.fill", label: "Inizia prossima serie", value: "next")
                } else {
                    Text(state.status.isEmpty ? "Tocca per aprire la scheda" : state.status)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                    Spacer(minLength: 0)
                    if !state.isDone { action("checkmark", label: "Conferma serie", value: "done") }
                }
            }.frame(height: 32)
        }
        .padding(.horizontal, 14).padding(.vertical, 10).foregroundStyle(.white)
        .widgetURL(URL(string: "pivot://workout/\(sessionID)?set=\(state.setID)"))
    }
    private var prescription: String {
        let current = state.kind == "Warm-up" ? "Warm-up \(state.number)" : "Serie \(state.workingNumber ?? state.number)"
        guard let sets = state.targetSets, let reps = state.targetReps else { return current }
        return "\(current) · obiettivo \(sets) × \(reps)\(state.isometric ? "" : " Reps")"
    }
    private func metric(_ title: String, value: String, minus: String, plus: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.75))
            HStack(spacing: 2) {
                Text(value).font(.system(size: state.separateSides && state.weighted ? 17 : 21, weight: .semibold))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if !resting {
                    action("minus", label: "Riduci \(title)", value: minus, compact: true)
                    action("plus", label: "Aumenta \(title)", value: plus, compact: true)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func action(_ icon: String, label: String, value: String, compact: Bool = false) -> some View {
        Button(intent: WorkoutActionIntent(sessionID: sessionID, setID: state.setID, action: value)) {
            Image(systemName: icon).font(.system(size: compact ? 12 : 16, weight: .semibold))
                .frame(width: compact ? 26 : 32, height: 32)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).foregroundStyle(.mint).accessibilityLabel(label)
    }
}
