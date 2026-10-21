import Foundation

struct CoachSavedCalendarDraft: Codable, Identifiable {
    var id = UUID()
    var messageID: UUID
    var userMessageID: UUID? = nil
    var dayKey: String
    var draft: CoachCalendarDraft
    var calendarID: String? = nil
    var createdAt = Date()
    var updatedAt = Date()
    var createdEventID: String? = nil
    var creationOptions: CalendarCreationOptions? = nil
    var creationNeedsVerification: Bool? = nil
}

enum CoachDraftStore {
    @discardableResult static func completeCreation(id: UUID, receipt: CalendarCreationReceipt, options: CalendarCreationOptions,
        data: inout AppData, now: Date = Date()) -> Bool {
        var next = data
        guard let saved = next.coachState.calendarDrafts?.first(where: { $0.id == id }),
              saved.calendarID == receipt.activity.calendarIdentifier,
              CalendarCreationBundle.existing(parts: options.parts(draft: saved.draft, creationID: id),
                  items: receipt.travel.map { [$0, receipt.activity] } ?? [receipt.activity]),
              CalendarActivityLinks.capture(id: id, receipt: receipt, options: options, data: &next, now: now),
              markCreated(id: id, eventID: receipt.activity.id, calendarID: receipt.activity.calendarIdentifier, data: &next, now: now) else { return false }
        data = next; return true
    }
    static func valid(_ coach: CoachState) -> Bool {
        let drafts = coach.calendarDrafts ?? []
        guard Set(drafts.map(\.id)).count == drafts.count,
              Set(drafts.map(\.messageID)).count == drafts.count else { return false }
        let messages = Dictionary(coach.messages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return drafts.allSatisfy { saved in
            guard let message = messages[saved.messageID], message.role == .coach, message.dayKey == saved.dayKey,
                  saved.draft.title.count <= 160, saved.draft.notes.count <= 3000,
                  (saved.draft.calendarHint?.count ?? 0) <= 160,
                  saved.calendarID.map({ !$0.isEmpty && $0.count <= 1024 }) ?? true,
                  saved.createdEventID.map({ !$0.isEmpty && $0.count <= 2048 }) ?? true,
                  saved.creationOptions?.isValid ?? true else { return false }
            if let userID = saved.userMessageID {
                guard let user = messages[userID], user.role == .user, user.dayKey == saved.dayKey else { return false }
            }
            // Incomplete edits may be kept; only the final creation gate
            // requires complete valid times and a nonempty title/calendar.
            return (saved.draft.start.map { $0.timeIntervalSinceReferenceDate.isFinite } ?? true)
                && (saved.draft.end.map { $0.timeIntervalSinceReferenceDate.isFinite } ?? true)
        }
    }
    @discardableResult static func update(id: UUID, draft: CoachCalendarDraft, calendarID: String?,
                                         data: inout AppData, now: Date = Date(), options: CalendarCreationOptions? = nil) -> Bool {
        var coach = data.coachState
        guard let index = coach.calendarDrafts?.firstIndex(where: { $0.id == id }),
              coach.calendarDrafts?[index].createdEventID == nil else { return false }
        if let previous = coach.calendarDrafts?[index], previous.creationNeedsVerification == true {
            guard previous.draft == draft, previous.calendarID == calendarID,
                  options == nil || previous.creationOptions == options else { return false }
        }
        coach.calendarDrafts?[index].draft = draft
        coach.calendarDrafts?[index].calendarID = calendarID
        if let options { coach.calendarDrafts?[index].creationOptions = options }
        coach.calendarDrafts?[index].updatedAt = now
        guard valid(coach) else { return false }
        data.coachState = coach; return true
    }
    @discardableResult static func markCreated(id: UUID, eventID: String, calendarID: String, data: inout AppData, now: Date = Date()) -> Bool {
        var coach = data.coachState
        guard now.timeIntervalSinceReferenceDate.isFinite,
              let index = coach.calendarDrafts?.firstIndex(where: { $0.id == id }),
              coach.calendarDrafts?[index].createdEventID.map({ $0 == eventID }) ?? true else { return false }
        coach.calendarDrafts?[index].createdEventID = eventID
        coach.calendarDrafts?[index].creationNeedsVerification = false
        coach.calendarDrafts?[index].calendarID = calendarID
        coach.calendarDrafts?[index].updatedAt = now
        if coach.focusedCalendarDraftID == id {
            coach.focusedCalendarDraftID = nil; coach.omitPreviousDraft = true
            coach.contextStartedAt = now
        }
        guard valid(coach) else { return false }
        data.coachState = coach; return true
    }
}
