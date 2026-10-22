import SwiftUI

struct CoachDraftCard: View {
    let saved: CoachSavedCalendarDraft
    var open: () -> Void
    var body: some View {
        if saved.createdEventID == nil {
            Button(action: open) {
                PivotCard(tint: PivotTheme.blue) {
                    Label("Bozza da controllare", systemImage: "calendar.badge.plus").font(.caption).foregroundStyle(PivotTheme.blue)
                    Text(saved.draft.title.isEmpty ? "Nuovo impegno" : saved.draft.title).font(.headline).foregroundStyle(PivotTheme.text)
                    if let start = saved.draft.start { Text(DisplayDate.label(start, format: "d MMM · HH:mm")).font(.subheadline).foregroundStyle(PivotTheme.muted) }
                    Label("Apri e modifica", systemImage: "arrow.up.right.square").font(.subheadline.weight(.semibold)).foregroundStyle(PivotTheme.accent)
                }
            }.buttonStyle(.plain).accessibilityIdentifier("coach-saved-draft-" + saved.id.uuidString)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Creato nel Calendario", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(PivotTheme.accent)
                    .accessibilityIdentifier("coach-draft-created-" + saved.id.uuidString)
                if let options = saved.creationOptions, let travel = options.appleCalendarTravel {
                    Label("Completa il tempo di percorrenza in Calendario Apple", systemImage: "calendar.badge.clock")
                        .font(.subheadline).foregroundStyle(PivotTheme.amber).accessibilityIdentifier("coach-apple-travel-handoff")
                    Text("Apri ‘\(saved.draft.title)’ → Modifica → Tempo di percorrenza.\nDa: \(travel.origin)\nA: \(options.location)\nStima: \(travel.minutes) min.")
                        .font(.caption).foregroundStyle(PivotTheme.muted).textSelection(.enabled)
                    Text("Pivot non può verificare la fascia Apple: se l’hai già completata, non aggiungere un secondo viaggio.")
                        .font(.caption).foregroundStyle(PivotTheme.muted)
                }
            }
        }
    }
}
