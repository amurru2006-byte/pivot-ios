import SwiftUI

/// Inserted into the safe area, not the scrolling list: even the final exercise
/// has the same reachable controls, and the last rows remain unobscured.
struct WorkoutRecoveryBar: View {
    let session: TrainingSession
    let next: TrainingWorkoutContext.Selection?
    let pause: () -> Void
    let reset: () -> Void
    let advance: () -> Void
    @State private var minimized = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if minimized {
                HStack(spacing: 12) {
                    if let rest = session.rest {
                        TimelineView(.periodic(from: Date(), by: 1)) { context in
                            Text(ActivityTiming.duration(rest.remaining(at: context.date)))
                                .font(.title3.bold()).monospacedDigit().accessibilityIdentifier("workout-rest-countdown")
                        }
                    }
                    Text(next?.exercise.name ?? (session.rest == nil ? "Serie registrate" : "Ultimo recupero"))
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    control("chevron.up", label: "Espandi controlli allenamento", id: "workout-rest-expand", action: { setMinimized(false) })
                }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            } else {
                expandedControls
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .foregroundStyle(PivotTheme.accent)
        .background(PivotTheme.surface)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain).accessibilityIdentifier("workout-recovery-bar")
        .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { value in
            guard abs(value.translation.height) > abs(value.translation.width) else { return }
            if value.translation.height > 24 { setMinimized(true) }
            else if value.translation.height < -24 { setMinimized(false) }
        })
    }
    private var expandedControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let rest = session.rest {
                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rest.deadline == nil ? "Recupero in pausa" : rest.remaining(at: context.date) == 0 ? "Recupero terminato" : "Recupero")
                                .font(.caption.weight(.semibold)).foregroundStyle(PivotTheme.muted)
                            Text(ActivityTiming.duration(rest.remaining(at: context.date)))
                                .font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit()
                                .accessibilityIdentifier("workout-rest-countdown")
                        }
                        Spacer(minLength: 0)
                        control(rest.deadline == nil ? "play.fill" : "pause.fill", label: rest.deadline == nil ? "Riprendi recupero" : "Pausa recupero", id: "workout-rest-pause", action: pause)
                        control("arrow.counterclockwise", label: "Reset recupero", id: "workout-rest-reset", action: reset)
                        control("chevron.down", label: "Riduci barra recupero", id: "workout-rest-collapse", action: { setMinimized(true) })
                    }
                }
                if let origin = TrainingWorkoutContext.restOrigin(in: session) {
                    Text(origin.exercise.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        .accessibilityIdentifier("workout-rest-exercise")
                }
            }
            HStack(spacing: 8) {
                Button(action: advance) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(next.map { session.rest == nil ? $0.exercise.name : "Prossima · " + $0.exercise.name } ?? (session.rest == nil ? "Serie registrate" : "Chiudi recupero"))
                                .font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(next?.prescription ?? (session.rest == nil ? "Puoi terminare l’allenamento" : "Conserva il tempo effettivo"))
                                .font(.caption).foregroundStyle(PivotTheme.muted).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.right").font(.headline).accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("workout-next-set")
                .disabled(next == nil && session.rest == nil)
                if session.rest == nil {
                    control("chevron.down", label: "Riduci controlli allenamento", id: "workout-rest-collapse", action: { setMinimized(true) })
                }
            }
        }
    }
    private func setMinimized(_ value: Bool) { withAnimation(.easeInOut(duration: 0.18)) { minimized = value } }
    private func control(_ icon: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title3.weight(.semibold))
                .frame(width: 48, height: 48)
                .background(PivotTheme.raised, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(id)
    }
}
