import ActivityKit
import WidgetKit
import SwiftUI

@main
struct PivotWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutAttributes.self) { context in
            WorkoutLiveView(sessionID: context.attributes.sessionID, state: context.state)
                .activityBackgroundTint(Color(red: 0.08, green: 0.14, blue: 0.15))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "dumbbell.fill").foregroundStyle(.mint) }
                DynamicIslandExpandedRegion(.trailing) { Text(context.state.kind == "Warm-up" ? "W\(context.state.number)" : "Serie \(context.state.workingNumber ?? context.state.number)").font(.caption) }
                DynamicIslandExpandedRegion(.bottom) { WorkoutLiveView(sessionID: context.attributes.sessionID, state: context.state) }
            } compactLeading: { Image(systemName: "dumbbell.fill") }
              compactTrailing: {
                if let end = context.state.deadline { Text(timerInterval: Date()...max(Date(), end), countsDown: true).monospacedDigit().frame(width: 48) }
                else if let seconds = context.state.pausedSeconds { Text("Ⅱ \(seconds)s").monospacedDigit().frame(width: 58) }
                else { Text(context.state.isDone ? "✓" : context.state.kind == "Warm-up" ? "W\(context.state.number)" : "S\(context.state.workingNumber ?? context.state.number)") }
            } minimal: { Image(systemName: "dumbbell.fill") }
            .widgetURL(workoutURL(context))
        }
    }
}

private func workoutURL(_ context: ActivityViewContext<WorkoutAttributes>) -> URL? {
    URL(string: "pivot://workout/\(context.attributes.sessionID)?set=\(context.state.setID)")
}
