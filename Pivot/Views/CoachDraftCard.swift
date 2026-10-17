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
            Label("Creato nel Calendario", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(PivotTheme.accent)
                .accessibilityIdentifier("coach-draft-created-" + saved.id.uuidString)
        }
    }
}
