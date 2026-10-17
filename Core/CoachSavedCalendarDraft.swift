import Foundation

struct CoachSavedCalendarDraft: Codable, Identifiable {
    var id = UUID()
    var messageID: UUID
    var dayKey: String
    var draft: CoachCalendarDraft
    var calendarID: String? = nil
    var createdAt = Date()
    var updatedAt = Date()
    var createdEventID: String? = nil
}

enum CoachDraftStore {
    static func valid(_ coach: CoachState) -> Bool {
        let drafts = coach.calendarDrafts ?? []
        guard Set(drafts.map(\.id)).count == drafts.count else { return false }
        let messages = Dictionary(coach.messages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return drafts.allSatisfy { saved in
            guard let message = messages[saved.messageID], message.role == .coach, message.dayKey == saved.dayKey,
                  saved.draft.title.count <= 160, saved.draft.notes.count <= 3000,
                  (saved.draft.calendarHint?.count ?? 0) <= 160,
                  saved.calendarID.map({ !$0.isEmpty && $0.count <= 1024 }) ?? true,
                  saved.createdEventID.map({ !$0.isEmpty && $0.count <= 2048 }) ?? true else { return false }
            // Incomplete edits may be kept; only the final creation gate
            // requires complete future times and a nonempty title/calendar.
            return (saved.draft.start.map { $0.timeIntervalSinceReferenceDate.isFinite } ?? true)
                && (saved.draft.end.map { $0.timeIntervalSinceReferenceDate.isFinite } ?? true)
        }
    }
    @discardableResult static func update(id: UUID, draft: CoachCalendarDraft, calendarID: String?,
                                         data: inout AppData, now: Date = Date()) -> Bool {
        var coach = data.coachState
        guard let index = coach.calendarDrafts?.firstIndex(where: { $0.id == id }),
              coach.calendarDrafts?[index].createdEventID == nil else { return false }
        coach.calendarDrafts?[index].draft = draft
        coach.calendarDrafts?[index].calendarID = calendarID
        coach.calendarDrafts?[index].updatedAt = now
        guard valid(coach) else { return false }
        data.coachState = coach; return true
    }
    @discardableResult static func markCreated(id: UUID, eventID: String, calendarID: String, data: inout AppData) -> Bool {
        var coach = data.coachState
        guard let index = coach.calendarDrafts?.firstIndex(where: { $0.id == id }),
              coach.calendarDrafts?[index].createdEventID.map({ $0 == eventID }) ?? true else { return false }
        coach.calendarDrafts?[index].createdEventID = eventID
        coach.calendarDrafts?[index].calendarID = calendarID
        coach.calendarDrafts?[index].updatedAt = Date()
        guard valid(coach) else { return false }
        data.coachState = coach; return true
    }
}
