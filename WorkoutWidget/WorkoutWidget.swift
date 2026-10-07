import ActivityKit
import WidgetKit
import SwiftUI

@main
struct PivotWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutAttributes.self) { context in
            WorkoutLockView(context: context)
                .activityBackgroundTint(Color(red: 0.08, green: 0.14, blue: 0.15))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text(context.state.exercise).font(.caption.bold()).lineLimit(2) }
                DynamicIslandExpandedRegion(.trailing) { Text("Serie \(context.state.number)").font(.caption) }
                DynamicIslandExpandedRegion(.bottom) { WorkoutLockView(context: context) }
            } compactLeading: { Image(systemName: "dumbbell.fill") }
              compactTrailing: {
                if let end = context.state.deadline { Text(timerInterval: Date()...max(Date(), end), countsDown: true).monospacedDigit().frame(width: 48) }
                else { Text("S\(context.state.number)") }
            } minimal: { Image(systemName: "dumbbell.fill") }
            .widgetURL(workoutURL(context))
        }
    }
}

private func workoutURL(_ context: ActivityViewContext<WorkoutAttributes>) -> URL? {
    URL(string: "pivot://workout/\(context.attributes.sessionID)?set=\(context.state.setID)")
}

private struct WorkoutLockView: View {
    let context: ActivityViewContext<WorkoutAttributes>
    private var state: WorkoutAttributes.ContentState { context.state }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(state.exercise).font(.subheadline.bold()).lineLimit(1)
                Spacer()
                Text("Serie \(state.number) · \(state.kind)").font(.caption).lineLimit(1)
            }
            if !state.isDone && state.isometric {
                HStack {
                    if state.separateSides {
                        control("Sx", value: "\(state.left ?? 0) s", minus: "left-", plus: "left+")
                        control("Dx", value: "\(state.right ?? 0) s", minus: "right-", plus: "right+")
                    } else { control("Durata", value: "\(state.seconds ?? 0) s", minus: "seconds-", plus: "seconds+") }
                }
                if state.weighted { control("Zavorra", value: "\((state.kg ?? 0).formatted()) kg", minus: "kg-", plus: "kg+") }
            } else if !state.isDone {
                HStack {
                    control("Carico", value: "\((state.kg ?? 0).formatted()) kg", minus: "kg-", plus: "kg+")
                    control("Reps", value: "\(state.reps ?? 0)", minus: "reps-", plus: "reps+")
                }
            }
            HStack {
                if let end = state.deadline {
                    Text("Recupero").font(.caption)
                    Text(timerInterval: Date()...max(Date(), end), countsDown: true).monospacedDigit()
                    action("Pausa", "pause")
                    action("Reset", "reset")
                    action("Prossima", "next")
                } else if let seconds = state.pausedSeconds {
                    Text("Pausa · \(seconds) s").font(.caption)
                    action("Riprendi", "pause"); action("Reset", "reset"); action("Prossima", "next")
                } else {
                    Text(state.status).font(.caption).lineLimit(2)
                    Spacer()
                    if !state.isDone { action("Fatta", "done") }
                }
            }
        }.padding(12).foregroundStyle(.white).widgetURL(workoutURL(context))
    }
    private func action(_ title: String, _ value: String) -> some View {
        Button(intent: WorkoutActionIntent(sessionID: context.attributes.sessionID, setID: state.setID, action: value)) { Text(title).font(.caption.bold()) }
            .tint(.mint).buttonStyle(.bordered)
    }
    private func control(_ title: String, value: String, minus: String, plus: String) -> some View {
        HStack(spacing: 6) {
            action("−", minus)
            VStack(spacing: 1) { Text(title).font(.caption2); Text(value).font(.caption.bold()).monospacedDigit() }
            action("+", plus)
        }.frame(maxWidth: .infinity)
    }
}
